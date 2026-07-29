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
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        let generatedFile = try await E2EHarness.runGeneratedFileSpeech(
            on: worker,
            id: "req-generated-file-e2e",
            text: E2EHarness.testingPlaybackText,
            profileName: E2EHarness.testingProfileName,
        )
        let artifactID = "req-generated-file-e2e-artifact-1"
        #expect(generatedFile["artifact_id"] as? String == artifactID)
        #expect(generatedFile["voice_profile"] as? String == E2EHarness.testingProfileName)

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

#if DEBUG
    @Test(
        .enabled(
            if: speakSwiftlyRetainedFileConsistencyE2ETestsEnabled(),
            "This repeated real-model diagnostic requires SPEAKSWIFTLY_RETAINED_FILE_CONSISTENCY_E2E=1.",
        ),
    )
    func `identical qwen big retained files preserve prepared conditioning`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        try sandbox.seedProfileFixture(.femmeDesign, as: E2EHarness.testingProfileName)

        let conservativeObservations = try await retainedFileConsistencyObservations(
            sandbox: sandbox,
            requestPrefix: "req-retained-consistency",
            iterationCount: 3,
            deterministicSampling: false,
        )
        let deterministicObservations = try await retainedFileConsistencyObservations(
            sandbox: sandbox,
            requestPrefix: "req-retained-deterministic",
            iterationCount: 2,
            deterministicSampling: true,
        )
        let observations = conservativeObservations + deterministicObservations

        let referenceFingerprints = Set(observations.map(\.referenceFingerprint))
        let textFingerprints = Set(observations.map(\.textFingerprint))
        #expect(referenceFingerprints.count == 1)
        #expect(textFingerprints.count == 1)
        #expect(observations.allSatisfy { $0.referenceUnchanged })
        #expect(conservativeObservations.allSatisfy { abs($0.temperature - 0.6) < 0.0001 })
        #expect(conservativeObservations.allSatisfy { abs($0.topP - 0.9) < 0.0001 })
        #expect(conservativeObservations.allSatisfy { $0.topK == 50 })
        #expect(deterministicObservations.allSatisfy { $0.temperature == 0 })
        #expect(deterministicObservations.allSatisfy { $0.topP == 1 })
        #expect(deterministicObservations.allSatisfy { $0.topK == 1 })
        #expect(observations.allSatisfy { abs($0.repetitionPenalty - 1.05) < 0.0001 })
        #expect(observations.allSatisfy { $0.primaryCodecTokenCount > 0 })
        #expect(observations.allSatisfy { $0.audioSampleCount > 0 })
        #expect(observations.allSatisfy { $0.fileByteCount > 0 })
        #expect(Set(deterministicObservations.map(\.primaryCodecTokenDigest)).count == 1)
        #expect(Set(deterministicObservations.map(\.audioSampleDigest)).count == 1)
        #expect(Set(deterministicObservations.map(\.audioSampleCount)).count == 1)

        print("Conservative retained-file observations: \(conservativeObservations)")
        print("Deterministic retained-file observations: \(deterministicObservations)")
    }
#endif
}

#if DEBUG
private func retainedFileConsistencyObservations(
    sandbox: E2ESandbox,
    requestPrefix: String,
    iterationCount: Int,
    deterministicSampling: Bool,
) async throws -> [RetainedFileConsistencyObservation] {
    let worker = try WorkerProcess(
        profileRootURL: sandbox.profileRootURL,
        silentPlayback: true,
        configuration: SpeakSwiftly.Configuration(
            speechBackend: .qwen3_BIG_8bit,
            qwenConditioningStrategy: .preparedConditioning,
        ),
        deterministicQwenSampling: deterministicSampling,
    )
    defer { Task { await worker.stop() } }

    try await E2EHarness.awaitWorkerReady(worker)
    let repeatedText = "Identical retained audio should keep this prepared voice profile stable across every generation."
    var observations = [RetainedFileConsistencyObservation]()

    for iteration in 1...iterationCount {
        let requestID = "\(requestPrefix)-\(iteration)"
        let generatedFile = try await E2EHarness.runGeneratedFileSpeech(
            on: worker,
            id: requestID,
            text: repeatedText,
            profileName: E2EHarness.testingProfileName,
        )
        let startedDebugEvent = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                $0["event"] as? String == "qwen_generation_debug_started"
                    && $0["request_id"] as? String == requestID
            },
        )
        let finishedDebugEvent = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                $0["event"] as? String == "qwen_generation_debug_finished"
                    && $0["request_id"] as? String == requestID
            },
        )
        try observations.append(
            RetainedFileConsistencyObservation(
                iteration: iteration,
                generatedFile: generatedFile,
                startedDebugEvent: startedDebugEvent,
                finishedDebugEvent: finishedDebugEvent,
            ),
        )
    }

    if iterationCount > 1 {
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["event"] as? String == "qwen_reference_conditioning_cache_hit"
                && $0["request_id"] as? String == "\(requestPrefix)-2"
        } != nil)
    }

    try worker.closeInput()
    try await worker.waitForExit(timeout: .seconds(30))
    return observations
}

private struct RetainedFileConsistencyObservation: CustomStringConvertible {
    let iteration: Int
    let referenceFingerprint: String
    let textFingerprint: String
    let primaryCodecTokenDigest: String
    let audioSampleDigest: String
    let referenceUnchanged: Bool
    let temperature: Double
    let topP: Double
    let topK: Int
    let repetitionPenalty: Double
    let primaryCodecTokenCount: Int
    let audioSampleCount: Int
    let fileByteCount: Int

    var description: String {
        "iteration=\(iteration), reference=\(referenceFingerprint), tokens=\(primaryCodecTokenDigest), audio=\(audioSampleDigest), samples=\(audioSampleCount), bytes=\(fileByteCount)"
    }

    init(
        iteration: Int,
        generatedFile: [String: Any],
        startedDebugEvent: [String: Any],
        finishedDebugEvent: [String: Any],
    ) throws {
        let startedDetails = try #require(startedDebugEvent["details"] as? [String: Any])
        let finishedDetails = try #require(finishedDebugEvent["details"] as? [String: Any])
        let filePath = try #require(generatedFile["file_path"] as? String)
        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)

        self.iteration = iteration
        referenceFingerprint = try #require(finishedDetails["reference_fingerprint_after"] as? String)
        textFingerprint = try #require(startedDetails["text_fingerprint"] as? String)
        primaryCodecTokenDigest = try #require(finishedDetails["primary_codec_token_digest"] as? String)
        audioSampleDigest = try #require(finishedDetails["audio_sample_digest"] as? String)
        referenceUnchanged = try #require(finishedDetails["reference_unchanged"] as? Bool)
        temperature = try #require(startedDetails["temperature"] as? Double)
        topP = try #require(startedDetails["top_p"] as? Double)
        topK = try #require(startedDetails["top_k"] as? Int)
        repetitionPenalty = try #require(startedDetails["repetition_penalty"] as? Double)
        primaryCodecTokenCount = try #require(finishedDetails["primary_codec_token_count"] as? Int)
        audioSampleCount = try #require(finishedDetails["audio_sample_count"] as? Int)
        fileByteCount = try #require(attributes[.size] as? Int)
    }
}
#endif
#endif
