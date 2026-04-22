#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .artifacts, .quick),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct GeneratedFileE2ETests {
    @Test func `managed reads`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-generated-file-profile",
            profileName: E2EHarness.testingProfileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )

        let generatedFile = try await E2EHarness.runGeneratedFileSpeech(
            on: worker,
            id: "req-generated-file-e2e",
            text: E2EHarness.testingPlaybackText,
            profileName: E2EHarness.testingProfileName,
        )
        let artifactID = "req-generated-file-e2e-artifact-1"
        #expect(generatedFile["artifact_id"] as? String == artifactID)
        #expect(generatedFile["profile_name"] as? String == E2EHarness.testingProfileName)

        let generatedFilePath = try #require(generatedFile["file_path"] as? String)
        #expect(FileManager.default.fileExists(atPath: generatedFilePath))

        try worker.sendJSON(
            """
            {"id":"req-generated-file-read","op":"get_generated_file","artifact_id":"\(artifactID)"}
            """,
        )

        let fetchedGeneratedFile = try #require(
            try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["id"] as? String == "req-generated-file-read",
                    $0["ok"] as? Bool == true,
                    let generatedFile = $0["generated_file"] as? [String: Any]
                else {
                    return false
                }

                return generatedFile["artifact_id"] as? String == artifactID
            },
        )
        let fetchedGeneratedFilePayload = try #require(fetchedGeneratedFile["generated_file"] as? [String: Any])
        #expect(fetchedGeneratedFilePayload["file_path"] as? String == generatedFilePath)

        try worker.sendJSON(
            """
            {"id":"req-generated-files-read","op":"list_generated_files"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["id"] as? String == "req-generated-files-read",
                $0["ok"] as? Bool == true,
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.contains {
                $0["artifact_id"] as? String == artifactID
                    && $0["file_path"] as? String == generatedFilePath
            }
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
