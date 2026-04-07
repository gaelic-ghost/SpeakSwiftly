import Foundation
import Testing
@testable import SpeakSwiftlyCore

extension SpeakSwiftlyE2ETests {
    @Suite("Generated File E2E")
    struct GeneratedFileSuite {
        @Test func generatedFileLaneRunsEndToEndAndSupportsManagedArtifactReads() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-generated-file-profile",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            let generatedFile = try await SpeakSwiftlyE2ETests.runGeneratedFileSpeech(
                on: worker,
                id: "req-generated-file-e2e",
                text: SpeakSwiftlyE2ETests.testingPlaybackText,
                profileName: SpeakSwiftlyE2ETests.testingProfileName
            )
            #expect(generatedFile["artifact_id"] as? String == "req-generated-file-e2e")
            #expect(generatedFile["profile_name"] as? String == SpeakSwiftlyE2ETests.testingProfileName)

            let generatedFilePath = try #require(generatedFile["file_path"] as? String)
            #expect(FileManager.default.fileExists(atPath: generatedFilePath))

            try worker.sendJSON(
                """
                {"id":"req-generated-file-read","op":"generated_file","artifact_id":"req-generated-file-e2e"}
                """
            )

            let fetchedGeneratedFile = try #require(
                try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                    guard
                        $0["id"] as? String == "req-generated-file-read",
                        $0["ok"] as? Bool == true,
                        let generatedFile = $0["generated_file"] as? [String: Any]
                    else {
                        return false
                    }

                    return generatedFile["artifact_id"] as? String == "req-generated-file-e2e"
                }
            )
            let fetchedGeneratedFilePayload = try #require(fetchedGeneratedFile["generated_file"] as? [String: Any])
            #expect(fetchedGeneratedFilePayload["file_path"] as? String == generatedFilePath)

            try worker.sendJSON(
                """
                {"id":"req-generated-files-read","op":"generated_files"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                guard
                    $0["id"] as? String == "req-generated-files-read",
                    $0["ok"] as? Bool == true,
                    let generatedFiles = $0["generated_files"] as? [[String: Any]]
                else {
                    return false
                }

                return generatedFiles.contains {
                    $0["artifact_id"] as? String == "req-generated-file-e2e"
                        && $0["file_path"] as? String == generatedFilePath
                }
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}
