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
struct GeneratedBatchE2ETests {
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
            id: "req-create-generated-batch-profile",
            profileName: E2EHarness.testingProfileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )

        let generatedBatch = try await E2EHarness.runGeneratedBatchSpeech(
            on: worker,
            id: "req-generated-batch-e2e",
            profileName: E2EHarness.testingProfileName,
            itemsJSON: """
            [
              {"text":"\(E2EHarness.testingPlaybackText.jsonEscaped)"},
              {"artifact_id":"custom-generated-batch-artifact","text":"\(E2EHarness.testingProfileText.jsonEscaped)","text_profile_id":"logs"}
            ]
            """,
        )

        #expect(generatedBatch["batch_id"] as? String == "req-generated-batch-e2e")
        #expect(generatedBatch["voice_profile"] as? String == E2EHarness.testingProfileName)
        #expect(generatedBatch["state"] as? String == "completed")

        let artifacts = try #require(generatedBatch["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == 2)

        let artifactIDs = artifacts.compactMap { $0["artifact_id"] as? String }
        #expect(artifactIDs.contains("req-generated-batch-e2e-artifact-1"))
        #expect(artifactIDs.contains("custom-generated-batch-artifact"))

        let artifactPaths = artifacts.compactMap { $0["file_path"] as? String }
        #expect(artifactPaths.count == 2)
        #expect(artifactPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) })

        try worker.sendJSON(
            """
            {"id":"req-generated-batch-read","op":"get_generated_batch","batch_id":"req-generated-batch-e2e"}
            """,
        )

        let fetchedGeneratedBatch = try #require(
            try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["id"] as? String == "req-generated-batch-read",
                    $0["ok"] as? Bool == true,
                    let generatedBatch = $0["generated_batch"] as? [String: Any],
                    let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
                else {
                    return false
                }

                return generatedBatch["batch_id"] as? String == "req-generated-batch-e2e"
                    && artifacts.count == 2
            },
        )
        let fetchedGeneratedBatchPayload = try #require(fetchedGeneratedBatch["generated_batch"] as? [String: Any])
        let fetchedArtifacts = try #require(fetchedGeneratedBatchPayload["artifacts"] as? [[String: Any]])
        #expect(Set(fetchedArtifacts.compactMap { $0["artifact_id"] as? String }) == Set(artifactIDs))

        try worker.sendJSON(
            """
            {"id":"req-generated-batches-read","op":"list_generated_batches"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["id"] as? String == "req-generated-batches-read",
                $0["ok"] as? Bool == true,
                let generatedBatches = $0["generated_batches"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatches.contains {
                guard
                    $0["batch_id"] as? String == "req-generated-batch-e2e",
                    let artifacts = $0["artifacts"] as? [[String: Any]]
                else {
                    return false
                }

                return artifacts.count == 2
            }
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
