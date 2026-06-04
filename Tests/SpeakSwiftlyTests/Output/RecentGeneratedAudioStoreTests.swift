import Foundation
import SpeakSwiftlyCore
import Testing

@Test func `recent generated audio store records active and completed items`() async throws {
    let store = RecentGeneratedAudioStore(limit: 5, memorySecondsPerItem: 10)
    let createdAt = Date(timeIntervalSince1970: 100)
    let completedAt = Date(timeIntervalSince1970: 101)
    let metadata = RecentGeneratedAudioMetadata(
        id: "recent-1",
        requestID: "request-1",
        textPreview: "Replay this later.",
        voiceProfileName: "swift-signal",
        createdAt: createdAt,
    )

    let active = await store.begin(metadata)
    #expect(active.id == "recent-1")
    #expect(active.requestID == "request-1")
    #expect(active.textPreview == "Replay this later.")
    #expect(active.voiceProfileName == "swift-signal")
    #expect(active.createdAt == createdAt)
    #expect(active.bufferState == .active)

    try await store.append(
        GeneratedAudioChunk(
            requestID: "request-1",
            sequenceNumber: 0,
            sampleRate: 10,
            channelCount: 1,
            samples: [0.1, 0.2, 0.3],
        ),
        to: "recent-1",
    )
    try await store.append(
        GeneratedAudioChunk(
            requestID: "request-1",
            sequenceNumber: 1,
            sampleRate: 10,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ),
        to: "recent-1",
    )

    let completed = try #require(
        await store.finish(
            id: "recent-1",
            completedAt: completedAt,
            artifactID: "artifact-1",
            artifactURL: URL(fileURLWithPath: "/tmp/recent-1.m4a"),
        ),
    )
    #expect(completed.bufferState == .complete)
    #expect(completed.completedAt == completedAt)
    #expect(completed.sampleRate == 10)
    #expect(completed.channelCount == 1)
    #expect(completed.durationSeconds == 0.3)
    #expect(completed.artifactID == "artifact-1")
    #expect(completed.bufferedChunkCount == 2)

    let chunks = await store.chunks(for: "recent-1")
    #expect(chunks.map(\.sequenceNumber) == [0, 1])
    #expect(chunks.last?.isFinal == true)
}

@Test func `recent generated audio store rejects chunks for the wrong request`() async throws {
    let store = RecentGeneratedAudioStore(limit: 5, memorySecondsPerItem: 10)
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-request",
            requestID: "expected-request",
            textPreview: "Wrong request should fail.",
            voiceProfileName: "swift-signal",
        ),
    )

    await #expect(throws: GeneratedAudioOutputError.self) {
        try await store.append(
            GeneratedAudioChunk(
                requestID: "other-request",
                sequenceNumber: 0,
                sampleRate: 24000,
                channelCount: 1,
                samples: [0.1],
            ),
            to: "recent-request",
        )
    }
}

@Test func `recent generated audio store trims buffered chunks by memory window`() async throws {
    let store = RecentGeneratedAudioStore(limit: 5, memorySecondsPerItem: 0.3)
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-trim",
            requestID: "request-trim",
            textPreview: "Keep only the newest chunks.",
            voiceProfileName: "swift-signal",
        ),
    )

    try await store.append(
        GeneratedAudioChunk(
            requestID: "request-trim",
            sequenceNumber: 0,
            sampleRate: 10,
            channelCount: 1,
            samples: [0.1, 0.2],
        ),
        to: "recent-trim",
    )
    try await store.append(
        GeneratedAudioChunk(
            requestID: "request-trim",
            sequenceNumber: 1,
            sampleRate: 10,
            channelCount: 1,
            samples: [0.3, 0.4],
        ),
        to: "recent-trim",
    )

    let chunks = await store.chunks(for: "recent-trim")
    #expect(chunks.map(\.sequenceNumber) == [1])
    #expect(chunks.first?.samples == [0.3, 0.4])

    let item = try #require(await store.item(id: "recent-trim"))
    #expect(item.durationSeconds == 0.4)
    #expect(item.bufferedChunkCount == 1)
}

@Test func `recent generated audio store evicts oldest items by limit`() async {
    let store = RecentGeneratedAudioStore(limit: 2, memorySecondsPerItem: 10)
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-1",
            requestID: "request-1",
            textPreview: "First",
            voiceProfileName: "swift-signal",
        ),
    )
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-2",
            requestID: "request-2",
            textPreview: "Second",
            voiceProfileName: "swift-signal",
        ),
    )
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-3",
            requestID: "request-3",
            textPreview: "Third",
            voiceProfileName: "swift-signal",
        ),
    )

    let snapshot = await store.snapshot()
    #expect(snapshot.items.map(\.id) == ["recent-2", "recent-3"])
    #expect(await store.item(id: "recent-1") == nil)
}

@Test func `recent generated audio store clamps limit and disables capture at zero`() async {
    let capped = RecentGeneratedAudioStore(limit: 99, memorySecondsPerItem: 10)
    #expect(await capped.snapshot().limit == 8)
    #expect(await capped.isCaptureEnabled())

    let disabled = RecentGeneratedAudioStore(limit: 0, memorySecondsPerItem: 10)
    #expect(await disabled.snapshot().limit == 0)
    #expect(await !(disabled.isCaptureEnabled()))

    await disabled.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-disabled",
            requestID: "request-disabled",
            textPreview: "Disabled capture should not retain this.",
            voiceProfileName: "swift-signal",
        ),
    )

    let snapshot = await disabled.snapshot()
    #expect(snapshot.items.isEmpty)
    #expect(await disabled.item(id: "recent-disabled") == nil)
}

@Test func `recent generated audio store records failed items and clears history`() async {
    let store = RecentGeneratedAudioStore(limit: 5, memorySecondsPerItem: 10)
    await store.begin(
        RecentGeneratedAudioMetadata(
            id: "recent-failed",
            requestID: "request-failed",
            textPreview: "This generation failed.",
            voiceProfileName: "swift-signal",
        ),
    )

    let failed = await store.fail(
        id: "recent-failed",
        message: "The generation stopped before a final audio chunk was produced.",
        completedAt: Date(timeIntervalSince1970: 200),
    )
    #expect(failed?.bufferState == .failed)
    #expect(failed?.failureMessage == "The generation stopped before a final audio chunk was produced.")

    await store.clear()
    let snapshot = await store.snapshot()
    #expect(snapshot.items.isEmpty)
}
