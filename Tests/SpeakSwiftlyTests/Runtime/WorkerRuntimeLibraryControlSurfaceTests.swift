import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

@Test func `library helpers submit profile and generated file worker protocol requests`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.voices
        .create(design: "bright-guide",
                from: "Hello there",
                vibe: .femme,
                voice: "Warm and bright",
                outputPath: nil)
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let listID = await runtime.voices.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == listID,
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            return profiles.contains { $0["profile_name"] as? String == "bright-guide" }
        }
    })

    let renameID = await runtime.voices.rename("bright-guide", to: "clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == renameID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })

    let renamedListID = await runtime.voices.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == renamedListID,
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            let names = profiles.compactMap { $0["profile_name"] as? String }
            return names.contains("clear-guide") && !names.contains("bright-guide")
        }
    })

    let rerollID = await runtime.voices.reroll("clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == rerollID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })

    let speakFileID = await runtime.generate
        .audio(
            text: "Save this request as an artifact.",
            voiceProfile: "clear-guide",
        )
        .id
    let fileArtifactID = "\(speakFileID)-artifact-1"
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == speakFileID,
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFileID = await runtime.artifacts.file(id: fileArtifactID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedFileID,
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFilesID = await runtime.artifacts.files().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedFilesID,
                $0["ok"] as? Bool == true,
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.contains {
                $0["artifact_id"] as? String == fileArtifactID
            }
        }
    })

    let generationJobID = await runtime.jobs.job(id: speakFileID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationJobID,
                $0["ok"] as? Bool == true,
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == speakFileID
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "completed"
                && (generationJob["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
        }
    })

    let generationJobsID = await runtime.jobs.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationJobsID,
                $0["ok"] as? Bool == true,
                let generationJobs = $0["generation_jobs"] as? [[String: Any]]
            else {
                return false
            }

            return generationJobs.contains {
                $0["job_id"] as? String == speakFileID
                    && $0["job_kind"] as? String == "file"
                    && $0["state"] as? String == "completed"
                    && ($0["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
            }
        }
    })

    let removeID = await runtime.voices.delete(named: "clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == removeID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })
}

@Test func `reroll rebuilds an existing profile in place from its stored inputs`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    let originalAudio = Data([0x01, 0x02, 0x03, 0x04])
    _ = try store.createProfile(
        profileName: "bright-guide",
        vibe: .femme,
        modelRepo: ModelFactory.profileModelRepo,
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: originalAudio,
    )

    let rerolledSamples: [Float] = [0.7, 0.8, 0.9]
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            AnySpeechModel(
                sampleRate: 24000,
                generate: { _, _, _, _, _, _ in rerolledSamples },
                generateSamplesStream: { _, _, _, _, _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.finish()
                    }
                },
            )
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let rerollID = await runtime.voices.reroll("bright-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == rerollID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let rerolledProfile = try store.loadProfile(named: "bright-guide")
    #expect(rerolledProfile.manifest.profileName == "bright-guide")
    #expect(rerolledProfile.manifest.sourceText == "Hello there")
    #expect(rerolledProfile.manifest.voiceDescription == "Warm and bright.")
    try expectAudioSamples(
        rawTestAudioSamples(from: Data(contentsOf: rerolledProfile.referenceAudioURL)),
        approximatelyEqualTo: [0.738_888_9, 0.844_444_45, 0.95],
    )
}

@Test func `voice design profile creation gain normalizes reference audio`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    let generatedSamples: [Float] = [0.05, -0.1, 0.2]
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            AnySpeechModel(
                sampleRate: 24000,
                generate: { _, _, _, _, _, _ in generatedSamples },
                generateSamplesStream: { _, _, _, _, _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.finish()
                    }
                },
            )
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.voices
        .create(design: "bright-guide",
                from: "Hello there",
                vibe: .femme,
                voice: "Warm and bright",
                outputPath: nil)
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let profile = try store.loadProfile(named: "bright-guide")
    #expect(try Data(contentsOf: profile.referenceAudioURL) == rawTestAudioData(for: [0.2375, -0.475, 0.95]))
}

@Test func `clone profile creation gain normalizes imported reference audio`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    let referenceDirectory = makeTempDirectoryURL()
    defer {
        try? FileManager.default.removeItem(at: storeRoot)
        try? FileManager.default.removeItem(at: referenceDirectory)
    }

    let referenceAudioURL = referenceDirectory.appendingPathComponent("reference.wav")
    try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true)
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: referenceAudioURL)

    let store = try makeProfileStore(rootURL: storeRoot)
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        loadedCloneAudioSamples: [0.05, -0.1, 0.2],
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.voices
        .create(clone: "imported-guide",
                from: referenceAudioURL,
                vibe: .femme,
                transcript: "Hello there")
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "imported-guide"
        }
    })

    let profile = try store.loadProfile(named: "imported-guide")
    #expect(try Data(contentsOf: profile.referenceAudioURL) == rawTestAudioData(for: [0.2375, -0.475, 0.95]))
}

@Test func `create profile resolves relative output path against explicit caller working directory`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    let callerWorkingDirectory = makeTempDirectoryURL()
    defer {
        try? FileManager.default.removeItem(at: storeRoot)
        try? FileManager.default.removeItem(at: callerWorkingDirectory)
    }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let exportURL = callerWorkingDirectory.appendingPathComponent("exports/voice.wav")
    await runtime.accept(
        line: #"{"id":"req-relative-export","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav","cwd":"\#(callerWorkingDirectory.path)"}"#,
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-relative-export"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })
    #expect(FileManager.default.fileExists(atPath: exportURL.path))
}

@Test func `create profile rejects relative output path without explicit caller working directory`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-relative-export-missing-cwd","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav"}"#,
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            ($0["id"] as? String) == "req-relative-export-missing-cwd"
                && ($0["ok"] as? Bool) == false
                && ($0["code"] as? String) == "invalid_request"
                && (($0["message"] as? String)?.contains("did not provide 'cwd'") ?? false)
        }
    })
}
