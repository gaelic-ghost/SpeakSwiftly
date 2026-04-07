import Foundation
import Testing
@testable import SpeakSwiftlyCore

// MARK: - Generation Job Store

@Test func generationJobStoreWritesLoadsListsAndTransitionsFileJobs() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    let createdAt = Date(timeIntervalSince1970: 1_234)
    let queued = try store.createFileJob(
        jobID: "job-file-1",
        profileName: "default-femme",
        textProfileName: "logs",
        speechBackend: .marvis,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "artifact-1",
            text: "Hello from a file job.",
            textProfileName: "logs",
            textContext: nil,
            sourceFormat: nil
        ),
        createdAt: createdAt
    )

    #expect(queued.jobID == "job-file-1")
    #expect(queued.jobKind == .file)
    #expect(queued.state == .queued)
    #expect(queued.profileName == "default-femme")
    #expect(queued.textProfileName == "logs")
    #expect(queued.speechBackend == .marvis)
    #expect(queued.items.count == 1)
    #expect(queued.items[0].artifactID == "artifact-1")

    let running = try store.markRunning(id: "job-file-1", startedAt: Date(timeIntervalSince1970: 1_235))
    #expect(running.state == .running)
    #expect(running.startedAt == Date(timeIntervalSince1970: 1_235))

    let completed = try store.markCompleted(
        id: "job-file-1",
        artifacts: [
            SpeakSwiftly.GenerationArtifact(
                artifactID: "artifact-1",
                kind: .audioWAV,
                createdAt: Date(timeIntervalSince1970: 1_236),
                filePath: "/tmp/generated.wav",
                sampleRate: 24_000,
                profileName: "default-femme",
                textProfileName: "logs"
            )
        ],
        completedAt: Date(timeIntervalSince1970: 1_237)
    )
    #expect(completed.state == .completed)
    #expect(completed.artifacts.count == 1)
    #expect(completed.artifacts[0].artifactID == "artifact-1")

    let loaded = try store.loadGenerationJob(id: "job-file-1")
    #expect(loaded == completed)

    let listed = try store.listGenerationJobs()
    #expect(listed == [completed])
}

@Test func generationJobStoreRejectsMissingJobs() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)

    #expect(throws: WorkerError(code: .generationJobNotFound, message: "Generation job 'missing-job' was not found in the SpeakSwiftly generation-job store.")) {
        _ = try store.loadGenerationJob(id: "missing-job")
    }
}

@Test func generationJobStoreWritesAndListsBatchJobs() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGenerationJobStore(rootURL: rootURL)
    let queued = try store.createBatchJob(
        jobID: "job-batch-1",
        profileName: "default-femme",
        textProfileName: nil,
        speechBackend: .marvis,
        items: [
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-batch-1-artifact-1",
                text: "First file",
                textProfileName: nil,
                textContext: nil,
                sourceFormat: nil
            ),
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-batch-1-artifact-2",
                text: "Second file",
                textProfileName: "logs",
                textContext: nil,
                sourceFormat: .swift
            ),
        ],
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(queued.jobKind == .batch)
    #expect(queued.state == .queued)
    #expect(queued.items.count == 2)
    #expect(queued.items[1].artifactID == "job-batch-1-artifact-2")

    let loaded = try store.loadGenerationJob(id: "job-batch-1")
    #expect(loaded == queued)
}
