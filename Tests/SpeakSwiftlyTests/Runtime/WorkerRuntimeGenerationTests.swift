import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Generated File Queueing

@Test func speakFileAcknowledgesQueueThenCompletesWithGeneratedFileMetadata() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01, 0x02])
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let requestID = await runtime.speak(
        text: "Hello from the generated file path.",
        with: "default-femme",
        as: .file,
        id: "req-file-1"
    ).id
    #expect(requestID == "req-file-1")

    #expect(await waitUntil {
        output.countJSONObjects {
            $0["id"] as? String == "req-file-1"
                && $0["ok"] as? Bool == true
        } == 2
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-1",
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == "req-file-1"
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "queued"
                && (generationJob["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == "req-file-1-artifact-1"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-file-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-file-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "writing_generated_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-1",
                let generationJob = $0["generation_job"] as? [String: Any],
                let generatedFile = $0["generated_file"] as? [String: Any],
                generatedFile["artifact_id"] as? String == "req-file-1-artifact-1",
                generatedFile["profile_name"] as? String == "default-femme",
                let filePath = generatedFile["file_path"] as? String
            else {
                return false
            }

            return generationJob["state"] as? String == "completed"
                && FileManager.default.fileExists(atPath: filePath)
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-file-1"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })
}

@Test func generatedFileReadOperationsRunDuringResidentWarmupWithoutQueueing() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    _ = try generatedFileStore.createGeneratedFile(
        artifactID: "req-file-lookup",
        profileName: "default-femme",
        textProfileName: nil,
        sampleRate: 24_000,
        audioData: Data([0x01, 0x02, 0x03])
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-generated-file","op":"get_generated_file","artifact_id":"req-file-lookup"}"#)
    await runtime.accept(line: #"{"id":"req-generated-files","op":"list_generated_files"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-generated-file"
                && $0["event"] as? String == "started"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-file",
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == "req-file-lookup"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-files",
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.count == 1
                && generatedFiles.first?["artifact_id"] as? String == "req-file-lookup"
        }
    })
    #expect(!output.containsJSONObject {
        ($0["id"] as? String == "req-generated-file" || $0["id"] as? String == "req-generated-files")
            && $0["event"] as? String == "queued"
    })

    await preloadGate.open()
}

@Test func generationJobReadOperationsRunDuringResidentWarmupWithoutQueueing() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createFileJob(
        jobID: "job-file-lookup",
        profileName: "default-femme",
        textProfileName: nil,
        speechBackend: .qwen3,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "job-file-lookup-artifact-1",
            text: "Hello from a persisted file job.",
            textProfileName: nil,
            textContext: nil,
            sourceFormat: nil
        ),
        createdAt: Date(timeIntervalSince1970: 1_234)
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-generation-job","op":"get_generation_job","job_id":"job-file-lookup"}"#)
    await runtime.accept(line: #"{"id":"req-generation-jobs","op":"list_generation_jobs"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-generation-job"
                && $0["event"] as? String == "started"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generation-job",
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == "job-file-lookup"
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "queued"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generation-jobs",
                let generationJobs = $0["generation_jobs"] as? [[String: Any]]
            else {
                return false
            }

            return generationJobs.count == 1
                && generationJobs.first?["job_id"] as? String == "job-file-lookup"
        }
    })
    #expect(!output.containsJSONObject {
        ($0["id"] as? String == "req-generation-job" || $0["id"] as? String == "req-generation-jobs")
            && $0["event"] as? String == "queued"
    })

    await preloadGate.open()
}

@Test func expireGenerationJobRemovesCompletedFileArtifactsAndKeepsExpiredJobReadable() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    let storedFile = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-file-artifact-1",
        profileName: "default-femme",
        textProfileName: nil,
        sampleRate: 24_000,
        audioData: Data([0x01, 0x02, 0x03])
    )
    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createFileJob(
        jobID: "job-expire-file",
        profileName: "default-femme",
        textProfileName: nil,
        speechBackend: .qwen3,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "job-expire-file-artifact-1",
            text: "Persisted file job",
            textProfileName: nil,
            textContext: nil,
            sourceFormat: nil
        ),
        createdAt: Date(timeIntervalSince1970: 3_000)
    )
    _ = try generationJobStore.markCompleted(
        id: "job-expire-file",
        artifacts: [
            SpeakSwiftly.GenerationArtifact(
                artifactID: storedFile.summary.artifactID,
                kind: .audioWAV,
                createdAt: storedFile.summary.createdAt,
                filePath: storedFile.summary.filePath,
                sampleRate: storedFile.summary.sampleRate,
                profileName: storedFile.summary.profileName,
                textProfileName: storedFile.summary.textProfileName
            )
        ],
        completedAt: Date(timeIntervalSince1970: 3_001)
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-expire-job","op":"expire_generation_job","job_id":"job-expire-file"}"#)
    await runtime.accept(line: #"{"id":"req-job-after-expire","op":"get_generation_job","job_id":"job-expire-file"}"#)
    await runtime.accept(line: #"{"id":"req-generated-files-after-expire","op":"list_generated_files"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-job-after-expire",
                let generationJob = $0["generation_job"] as? [String: Any],
                let artifacts = generationJob["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generationJob["state"] as? String == "expired"
                && artifacts.count == 1
                && artifacts[0]["artifact_id"] as? String == "job-expire-file-artifact-1"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-files-after-expire",
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.isEmpty
        }
    })
    #expect(!FileManager.default.fileExists(atPath: storedFile.directoryURL.path))

    await preloadGate.open()
}

@Test func expireGenerationJobKeepsExpiredBatchReadableWithoutArtifactFiles() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    let first = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-batch-artifact-1",
        profileName: "default-femme",
        textProfileName: nil,
        sampleRate: 24_000,
        audioData: Data([0x01])
    )
    let second = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-batch-artifact-2",
        profileName: "default-femme",
        textProfileName: "logs",
        sampleRate: 24_000,
        audioData: Data([0x02])
    )
    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createBatchJob(
        jobID: "job-expire-batch",
        profileName: "default-femme",
        textProfileName: nil,
        speechBackend: .qwen3,
        items: [
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-expire-batch-artifact-1",
                text: "First",
                textProfileName: nil,
                textContext: nil,
                sourceFormat: nil
            ),
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-expire-batch-artifact-2",
                text: "Second",
                textProfileName: "logs",
                textContext: nil,
                sourceFormat: nil
            ),
        ],
        createdAt: Date(timeIntervalSince1970: 3_100)
    )
    _ = try generationJobStore.markCompleted(
        id: "job-expire-batch",
        artifacts: [
            SpeakSwiftly.GenerationArtifact(
                artifactID: first.summary.artifactID,
                kind: .audioWAV,
                createdAt: first.summary.createdAt,
                filePath: first.summary.filePath,
                sampleRate: first.summary.sampleRate,
                profileName: first.summary.profileName,
                textProfileName: first.summary.textProfileName
            ),
            SpeakSwiftly.GenerationArtifact(
                artifactID: second.summary.artifactID,
                kind: .audioWAV,
                createdAt: second.summary.createdAt,
                filePath: second.summary.filePath,
                sampleRate: second.summary.sampleRate,
                profileName: second.summary.profileName,
                textProfileName: second.summary.textProfileName
            ),
        ],
        completedAt: Date(timeIntervalSince1970: 3_101)
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-expire-batch","op":"expire_generation_job","job_id":"job-expire-batch"}"#)
    await runtime.accept(line: #"{"id":"req-generated-batch-after-expire","op":"get_generated_batch","batch_id":"job-expire-batch"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-batch-after-expire",
                let generatedBatch = $0["generated_batch"] as? [String: Any],
                let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatch["batch_id"] as? String == "job-expire-batch"
                && generatedBatch["state"] as? String == "expired"
                && artifacts.isEmpty
        }
    })
    #expect(!FileManager.default.fileExists(atPath: first.directoryURL.path))
    #expect(!FileManager.default.fileExists(atPath: second.directoryURL.path))

    await preloadGate.open()
}

