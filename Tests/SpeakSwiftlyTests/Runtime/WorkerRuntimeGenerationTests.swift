import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - Generated File Queueing

@Test func `speak file acknowledges queue then completes with generated file metadata`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let requestID = await runtime.generate
        .audio(
            text: "Hello from the generated file path.",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.countJSONObjects {
            $0["id"] as? String == requestID
                && $0["ok"] as? Bool == true
        } == 2
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == requestID,
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == requestID
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "queued"
                && (generationJob["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == "\(requestID)-artifact-1"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_audio_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "writing_generated_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == requestID,
                let generationJob = $0["generation_job"] as? [String: Any],
                let generatedFile = $0["generated_file"] as? [String: Any],
                generatedFile["artifact_id"] as? String == "\(requestID)-artifact-1",
                generatedFile["voice_profile"] as? String == "default-femme",
                let filePath = generatedFile["file_path"] as? String
            else {
                return false
            }

            return generationJob["state"] as? String == "completed"
                && FileManager.default.fileExists(atPath: filePath)
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == requestID
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })
}

@Test func `generated file read operations run during resident warmup without queueing`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    _ = try generatedFileStore.createGeneratedFile(
        artifactID: "req-file-lookup",
        voiceProfile: "default-femme",
        textProfile: nil,
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
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

@Test func `generation job read operations run during resident warmup without queueing`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createFileJob(
        jobID: "job-file-lookup",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .qwen3,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "job-file-lookup-artifact-1",
            text: "Hello from a persisted file job.",
            textProfile: nil,
            inputTextContext: nil,
            requestContext: nil,
        ),
        createdAt: Date(timeIntervalSince1970: 1234),
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
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

@Test func `expire generation job removes completed file artifacts and keeps expired job readable`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    let storedFile = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-file-artifact-1",
        voiceProfile: "default-femme",
        textProfile: nil,
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )
    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createFileJob(
        jobID: "job-expire-file",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .qwen3,
        item: SpeakSwiftly.GenerationJobItem(
            artifactID: "job-expire-file-artifact-1",
            text: "Persisted file job",
            textProfile: nil,
            inputTextContext: nil,
            requestContext: nil,
        ),
        createdAt: Date(timeIntervalSince1970: 3000),
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
                voiceProfile: storedFile.summary.voiceProfile,
                textProfile: storedFile.summary.textProfile,
                inputTextContext: storedFile.summary.inputTextContext,
                requestContext: storedFile.summary.requestContext,
            ),
        ],
        completedAt: Date(timeIntervalSince1970: 3001),
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
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

@Test func `expire generation job keeps expired batch readable without artifact files`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    let first = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-batch-artifact-1",
        voiceProfile: "default-femme",
        textProfile: nil,
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01]),
    )
    let second = try generatedFileStore.createGeneratedFile(
        artifactID: "job-expire-batch-artifact-2",
        voiceProfile: "default-femme",
        textProfile: "logs",
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x02]),
    )
    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    _ = try generationJobStore.createBatchJob(
        jobID: "job-expire-batch",
        voiceProfile: "default-femme",
        textProfile: nil,
        speechBackend: .qwen3,
        items: [
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-expire-batch-artifact-1",
                text: "First",
                textProfile: nil,
                inputTextContext: nil,
                requestContext: nil,
            ),
            SpeakSwiftly.GenerationJobItem(
                artifactID: "job-expire-batch-artifact-2",
                text: "Second",
                textProfile: "logs",
                inputTextContext: nil,
                requestContext: nil,
            ),
        ],
        createdAt: Date(timeIntervalSince1970: 3100),
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
                voiceProfile: first.summary.voiceProfile,
                textProfile: first.summary.textProfile,
                inputTextContext: first.summary.inputTextContext,
                requestContext: first.summary.requestContext,
            ),
            SpeakSwiftly.GenerationArtifact(
                artifactID: second.summary.artifactID,
                kind: .audioWAV,
                createdAt: second.summary.createdAt,
                filePath: second.summary.filePath,
                sampleRate: second.summary.sampleRate,
                voiceProfile: second.summary.voiceProfile,
                textProfile: second.summary.textProfile,
                inputTextContext: second.summary.inputTextContext,
                requestContext: second.summary.requestContext,
            ),
        ],
        completedAt: Date(timeIntervalSince1970: 3101),
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
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
