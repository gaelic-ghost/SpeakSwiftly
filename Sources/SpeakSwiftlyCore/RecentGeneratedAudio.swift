import Foundation

public enum RecentGeneratedAudioBufferState: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case complete
    case evicted
    case failed
}

public enum RecentGeneratedAudioRetentionPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case recentCache = "recent_cache"
    case retainedArtifact = "retained_artifact"
}

public enum RecentGeneratedAudioReplayMode: String, Codable, Sendable, Equatable, CaseIterable {
    case enqueueNext = "enqueue_next"
    case enqueueAfterCurrent = "enqueue_after_current"
    case interruptCurrent = "interrupt_current"
}

public struct RecentGeneratedAudioMetadata: Codable, Sendable, Equatable {
    public let id: String
    public let requestID: String
    public let textPreview: String
    public let voiceProfileName: String
    public let createdAt: Date
    public let retentionPolicy: RecentGeneratedAudioRetentionPolicy

    public init(
        id: String = UUID().uuidString,
        requestID: String,
        textPreview: String,
        voiceProfileName: String,
        createdAt: Date = Date(),
        retentionPolicy: RecentGeneratedAudioRetentionPolicy = .recentCache,
    ) {
        self.id = id
        self.requestID = requestID
        self.textPreview = textPreview
        self.voiceProfileName = voiceProfileName
        self.createdAt = createdAt
        self.retentionPolicy = retentionPolicy
    }
}

public struct RecentGeneratedAudioItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let requestID: String
    public let textPreview: String
    public let voiceProfileName: String
    public let createdAt: Date
    public let completedAt: Date?
    public let sampleRate: Int?
    public let channelCount: Int?
    public let durationSeconds: Double?
    public let artifactID: String?
    public let artifactURL: URL?
    public let retentionPolicy: RecentGeneratedAudioRetentionPolicy
    public let bufferState: RecentGeneratedAudioBufferState
    public let bufferedChunkCount: Int
    public let failureMessage: String?

    public init(
        id: String,
        requestID: String,
        textPreview: String,
        voiceProfileName: String,
        createdAt: Date,
        completedAt: Date?,
        sampleRate: Int?,
        channelCount: Int?,
        durationSeconds: Double?,
        artifactID: String?,
        artifactURL: URL?,
        retentionPolicy: RecentGeneratedAudioRetentionPolicy,
        bufferState: RecentGeneratedAudioBufferState,
        bufferedChunkCount: Int,
        failureMessage: String?,
    ) {
        self.id = id
        self.requestID = requestID
        self.textPreview = textPreview
        self.voiceProfileName = voiceProfileName
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.durationSeconds = durationSeconds
        self.artifactID = artifactID
        self.artifactURL = artifactURL
        self.retentionPolicy = retentionPolicy
        self.bufferState = bufferState
        self.bufferedChunkCount = bufferedChunkCount
        self.failureMessage = failureMessage
    }
}

public struct RecentGeneratedAudioSnapshot: Codable, Sendable, Equatable {
    public let items: [RecentGeneratedAudioItem]
    public let limit: Int
    public let memorySecondsPerItem: Double

    public init(
        items: [RecentGeneratedAudioItem],
        limit: Int,
        memorySecondsPerItem: Double,
    ) {
        self.items = items
        self.limit = limit
        self.memorySecondsPerItem = memorySecondsPerItem
    }
}

public actor RecentGeneratedAudioStore {
    private struct Entry {
        var metadata: RecentGeneratedAudioMetadata
        var completedAt: Date?
        var sampleRate: Int?
        var channelCount: Int?
        var chunks: [GeneratedAudioChunk]
        var artifactID: String?
        var artifactURL: URL?
        var bufferState: RecentGeneratedAudioBufferState
        var failureMessage: String?
        var bufferedSampleFrameCount: Int
        var totalSampleFrameCount: Int

        var durationSeconds: Double? {
            guard let sampleRate, sampleRate > 0 else {
                return nil
            }

            return Double(totalSampleFrameCount) / Double(sampleRate)
        }
    }

    private let limit: Int
    private let memorySecondsPerItem: Double
    private var entries = [String: Entry]()
    private var order = [String]()

    public init(
        limit: Int = 5,
        memorySecondsPerItem: Double = 30,
    ) {
        self.limit = min(8, max(0, limit))
        self.memorySecondsPerItem = max(0, memorySecondsPerItem)
    }

    public func isCaptureEnabled() -> Bool {
        limit > 0
    }

    @discardableResult
    public func begin(_ metadata: RecentGeneratedAudioMetadata) -> RecentGeneratedAudioItem {
        let entry = Entry(
            metadata: metadata,
            completedAt: nil,
            sampleRate: nil,
            channelCount: nil,
            chunks: [],
            artifactID: nil,
            artifactURL: nil,
            bufferState: .active,
            failureMessage: nil,
            bufferedSampleFrameCount: 0,
            totalSampleFrameCount: 0,
        )
        entries[metadata.id] = entry
        order.removeAll { $0 == metadata.id }
        order.append(metadata.id)
        evictOldestIfNeeded()
        return item(from: entry)
    }

    public func append(_ chunk: GeneratedAudioChunk, to id: String) throws {
        guard var entry = entries[id] else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Recent generated audio item '\(id)' does not exist.",
            )
        }
        guard entry.metadata.requestID == chunk.requestID else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Recent generated audio item '\(id)' belongs to request '\(entry.metadata.requestID)', but received chunk for request '\(chunk.requestID)'.",
            )
        }
        guard entry.bufferState == .active else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Recent generated audio item '\(id)' is '\(entry.bufferState.rawValue)' and cannot accept more chunks.",
            )
        }

        if entry.sampleRate == nil {
            entry.sampleRate = chunk.sampleRate
            entry.channelCount = chunk.channelCount
        }
        entry.chunks.append(chunk)
        let sampleFrameCount = sampleFrameCount(in: chunk)
        entry.bufferedSampleFrameCount += sampleFrameCount
        entry.totalSampleFrameCount += sampleFrameCount
        trimBufferedChunks(&entry)
        entries[id] = entry
    }

    @discardableResult
    public func finish(
        id: String,
        completedAt: Date = Date(),
        artifactID: String? = nil,
        artifactURL: URL? = nil,
    ) -> RecentGeneratedAudioItem? {
        guard var entry = entries[id] else {
            return nil
        }

        entry.completedAt = completedAt
        entry.artifactID = artifactID
        entry.artifactURL = artifactURL
        entry.bufferState = .complete
        entry.failureMessage = nil
        entries[id] = entry
        evictOldestIfNeeded()
        return item(from: entry)
    }

    @discardableResult
    public func fail(
        id: String,
        message: String,
        completedAt: Date = Date(),
    ) -> RecentGeneratedAudioItem? {
        guard var entry = entries[id] else {
            return nil
        }

        entry.completedAt = completedAt
        entry.bufferState = .failed
        entry.failureMessage = message
        entries[id] = entry
        evictOldestIfNeeded()
        return item(from: entry)
    }

    public func snapshot() -> RecentGeneratedAudioSnapshot {
        RecentGeneratedAudioSnapshot(
            items: order.compactMap { id in
                entries[id].map(item(from:))
            },
            limit: limit,
            memorySecondsPerItem: memorySecondsPerItem,
        )
    }

    public func item(id: String) -> RecentGeneratedAudioItem? {
        entries[id].map(item(from:))
    }

    public func chunks(for id: String) -> [GeneratedAudioChunk] {
        entries[id]?.chunks ?? []
    }

    public func clear() {
        entries.removeAll()
        order.removeAll()
    }

    private func evictOldestIfNeeded() {
        guard limit > 0 else {
            entries.removeAll()
            order.removeAll()
            return
        }

        while order.count > limit, let evictedID = order.first {
            order.removeFirst()
            if var evictedEntry = entries[evictedID] {
                evictedEntry.chunks.removeAll()
                evictedEntry.bufferState = .evicted
                entries[evictedID] = evictedEntry
                entries.removeValue(forKey: evictedID)
            }
        }
    }

    private func trimBufferedChunks(_ entry: inout Entry) {
        guard memorySecondsPerItem > 0,
              let sampleRate = entry.sampleRate,
              sampleRate > 0 else {
            entry.chunks.removeAll()
            entry.bufferedSampleFrameCount = 0
            return
        }

        let maxSampleFrames = Int((memorySecondsPerItem * Double(sampleRate)).rounded(.down))
        while entry.bufferedSampleFrameCount > maxSampleFrames,
              let firstChunk = entry.chunks.first {
            entry.bufferedSampleFrameCount -= sampleFrameCount(in: firstChunk)
            entry.chunks.removeFirst()
        }
    }

    private func sampleFrameCount(in chunk: GeneratedAudioChunk) -> Int {
        guard chunk.channelCount > 0 else {
            return 0
        }

        return chunk.samples.count / chunk.channelCount
    }

    private func item(from entry: Entry) -> RecentGeneratedAudioItem {
        RecentGeneratedAudioItem(
            id: entry.metadata.id,
            requestID: entry.metadata.requestID,
            textPreview: entry.metadata.textPreview,
            voiceProfileName: entry.metadata.voiceProfileName,
            createdAt: entry.metadata.createdAt,
            completedAt: entry.completedAt,
            sampleRate: entry.sampleRate,
            channelCount: entry.channelCount,
            durationSeconds: entry.durationSeconds,
            artifactID: entry.artifactID,
            artifactURL: entry.artifactURL,
            retentionPolicy: entry.metadata.retentionPolicy,
            bufferState: entry.bufferState,
            bufferedChunkCount: entry.chunks.count,
            failureMessage: entry.failureMessage,
        )
    }
}
