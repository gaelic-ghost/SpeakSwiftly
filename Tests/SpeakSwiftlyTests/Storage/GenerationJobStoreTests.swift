import Foundation
@testable import SpeakSwiftly
import Testing

// MARK: - Generation Job Store

@Test func `generation job store writes loads lists and transitions file jobs`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    let createdAt = Date(timeIntervalSince1970: 1234)
    let queued = try store.createFileJob(
        jobID: "job-file-1",
        voiceProfile: "default-femme",
        textProfile: "logs",
        speechBackend: .marvis,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "artifact-1",
            text: "Hello from a file job.",
            textProfile: "logs",
            sourceFormat: nil,
            requestContext: nil,
        ),
        createdAt: createdAt,
    )

    #expect(queued.jobID == "job-file-1")
    #expect(queued.jobKind == .file)
    #expect(queued.state == .queued)
    #expect(queued.voiceProfile == "default-femme")
    #expect(queued.textProfile == "logs")
    #expect(queued.speechBackend == .marvis)
    #expect(queued.items.count == 1)
    #expect(queued.items[0].artifactID == "artifact-1")

    let running = try store.markRunning(id: "job-file-1", startedAt: Date(timeIntervalSince1970: 1235))
    #expect(running.state == .running)
    #expect(running.startedAt == Date(timeIntervalSince1970: 1235))

    let completed = try store.markCompleted(
        id: "job-file-1",
        artifacts: [
            SpeakSwiftly.GenerationArtifact(
                artifactID: "artifact-1",
                kind: .audioWAV,
                createdAt: Date(timeIntervalSince1970: 1236),
                filePath: "/tmp/generated.wav",
                sampleRate: 24000,
                voiceProfile: "default-femme",
                textProfile: "logs",
                sourceFormat: nil,
                requestContext: nil,
            ),
        ],
        completedAt: Date(timeIntervalSince1970: 1237),
    )
    #expect(completed.state == .completed)
    #expect(completed.artifacts.count == 1)
    #expect(completed.artifacts[0].artifactID == "artifact-1")

    let loaded = try store.loadGenerationJob(id: "job-file-1")
    #expect(loaded == completed)

    let listed = try store.listGenerationJobs()
    #expect(listed == [completed])
}

@Test func `generation job store lists readable jobs when stale retained manifests exist`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    let queued = try store.createFileJob(
        jobID: "job-file-readable",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .qwen3,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "artifact-readable",
            text: "Readable retained job.",
            textProfile: nil,
            sourceFormat: nil,
            requestContext: nil,
        ),
        createdAt: Date(timeIntervalSince1970: 3000),
    )

    let staleJobID = "job-file-stale"
    let staleDirectoryURL = store.generationJobDirectoryURL(for: staleJobID)
    try FileManager.default.createDirectory(at: staleDirectoryURL, withIntermediateDirectories: false)
    let staleManifest = """
    {
      "artifacts" : [],
      "created_at" : "2026-04-16T17:46:21Z",
      "items" : [],
      "job_id" : "\(staleJobID)",
      "job_kind" : "file",
      "profile_name" : "default-femme",
      "retention_policy" : "manual",
      "speech_backend" : "qwen3",
      "state" : "failed",
      "updated_at" : "2026-04-16T17:46:21Z"
    }
    """
    try Data(staleManifest.utf8).write(to: store.manifestURL(for: staleDirectoryURL))

    #expect(try store.listGenerationJobs() == [queued])
    #expect(throws: WorkerError.self) {
        _ = try store.loadGenerationJob(id: staleJobID)
    }
}

@Test func `generation job store rejects missing jobs`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)

    #expect(throws: WorkerError(code: .generationJobNotFound, message: "Generation job 'missing-job' was not found in the SpeakSwiftly generation-job store.")) {
        _ = try store.loadGenerationJob(id: "missing-job")
    }
}

@Test func `generation job store writes and lists batch jobs`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    let queued = try store.createBatchJob(
        jobID: "job-batch-1",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .marvis,
        items: [
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-batch-1-artifact-1",
                text: "First file",
                textProfile: nil,
                sourceFormat: nil,
                requestContext: nil,
            ),
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-batch-1-artifact-2",
                text: "Second file",
                textProfile: "logs",
                sourceFormat: .swift,
                requestContext: nil,
            ),
        ],
        createdAt: Date(timeIntervalSince1970: 2000),
    )

    #expect(queued.jobKind == .batch)
    #expect(queued.state == .queued)
    #expect(queued.items.count == 2)
    #expect(queued.items[1].artifactID == "job-batch-1-artifact-2")

    let loaded = try store.loadGenerationJob(id: "job-batch-1")
    #expect(loaded == queued)
}

@Test func `generation job store expires completed jobs without dropping artifact metadata`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    _ = try store.createFileJob(
        jobID: "job-file-2",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .marvis,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "artifact-2",
            text: "Hello from a completed file job.",
            textProfile: nil,
            sourceFormat: nil,
            requestContext: nil,
        ),
        createdAt: Date(timeIntervalSince1970: 2100),
    )

    _ = try store.markCompleted(
        id: "job-file-2",
        artifacts: [
            SpeakSwiftly.GenerationArtifact(
                artifactID: "artifact-2",
                kind: .audioWAV,
                createdAt: Date(timeIntervalSince1970: 2101),
                filePath: "/tmp/artifact-2.wav",
                sampleRate: 24000,
                voiceProfile: "default-femme",
                textProfile: nil,
                sourceFormat: nil,
                requestContext: nil,
            ),
        ],
        completedAt: Date(timeIntervalSince1970: 2102),
    )

    let expired = try store.markExpired(
        id: "job-file-2",
        expiredAt: Date(timeIntervalSince1970: 2103),
    )

    #expect(expired.state == .expired)
    #expect(expired.expiresAt == Date(timeIntervalSince1970: 2103))
    #expect(expired.completedAt == Date(timeIntervalSince1970: 2102))
    #expect(expired.artifacts.count == 1)
    #expect(expired.artifacts[0].artifactID == "artifact-2")
}

@Test func `generation job store rejects expiring queued jobs`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    _ = try store.createFileJob(
        jobID: "job-file-queued",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .marvis,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "artifact-queued",
            text: "Queued",
            textProfile: nil,
            sourceFormat: nil,
            requestContext: nil,
        ),
        createdAt: Date(timeIntervalSince1970: 2200),
    )

    #expect(
        throws: WorkerError(
            code: .generationJobNotExpirable,
            message: "Generation job 'job-file-queued' is still queued and cannot be expired until it has either completed or failed.",
        ),
    ) {
        _ = try store.markExpired(id: "job-file-queued", expiredAt: Date(timeIntervalSince1970: 2201))
    }
}
