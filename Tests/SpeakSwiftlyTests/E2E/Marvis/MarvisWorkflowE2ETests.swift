#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

enum MarvisRouteCase: String, CaseIterable, Sendable {
    case femme
    case mascClone
    case androgenous

    var profileName: String {
        switch self {
            case .femme:
                "marvis-femme-profile"
            case .mascClone:
                "marvis-masc-clone-profile"
            case .androgenous:
                "marvis-androgenous-profile"
        }
    }

    var createRequestID: String {
        switch self {
            case .femme:
                "req-create-marvis-femme"
            case .mascClone:
                "req-create-marvis-clone"
            case .androgenous:
                "req-create-marvis-androgenous"
        }
    }

    var liveRequestID: String {
        switch self {
            case .femme:
                "req-live-marvis-femme"
            case .mascClone:
                "req-live-marvis-masc"
            case .androgenous:
                "req-live-marvis-androgenous"
        }
    }

    var vibe: SpeakSwiftly.Vibe {
        switch self {
            case .femme:
                .femme
            case .mascClone:
                .masc
            case .androgenous:
                .androgenous
        }
    }

    var voiceDescription: String {
        switch self {
            case .femme:
                "A warm, bright, feminine narrator voice."
            case .mascClone:
                E2EHarness.testingProfileVoiceDescription
            case .androgenous:
                "A calm, balanced, and gentle speaking voice."
        }
    }

    var expectedVoice: String {
        switch self {
            case .mascClone:
                "conversational_b"
            case .femme, .androgenous:
                "conversational_a"
        }
    }

    var usesCloneFixture: Bool {
        self == .mascClone
    }
}

private struct MarvisProfileLane: Sendable {
    let createID: String
    let liveID: String
    let profileName: String
    let vibe: SpeakSwiftly.Vibe
    let voiceDescription: String
    let expectedVoice: String

    static let all: [Self] = [
        Self(
            createID: "req-create-marvis-triplet-femme",
            liveID: "req-live-marvis-triplet-femme",
            profileName: "marvis-triplet-femme-profile",
            vibe: .femme,
            voiceDescription: "A warm, bright, feminine narrator voice.",
            expectedVoice: "conversational_a",
        ),
        Self(
            createID: "req-create-marvis-triplet-masc",
            liveID: "req-live-marvis-triplet-masc",
            profileName: "marvis-triplet-masc-profile",
            vibe: .masc,
            voiceDescription: "A grounded, rich, masculine speaking voice.",
            expectedVoice: "conversational_b",
        ),
        Self(
            createID: "req-create-marvis-triplet-androgenous",
            liveID: "req-live-marvis-triplet-androgenous",
            profileName: "marvis-triplet-androgenous-profile",
            vibe: .androgenous,
            voiceDescription: "A calm, balanced, and gentle speaking voice.",
            expectedVoice: "conversational_a",
        ),
    ]
}

@Suite(
    "Marvis E2E",
    .serialized,
    .tags(.e2e, .marvis),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct MarvisE2ETests {
    @Test("routes expected conversational voice", arguments: MarvisRouteCase.allCases)
    func routesExpectedConversationalVoice(testCase: MarvisRouteCase) async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .marvis,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)

        if testCase.usesCloneFixture {
            let fixtureProfileName = "marvis-clone-source"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/marvis-clone-reference.wav")

            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: "req-create-marvis-clone-fixture",
                profileName: fixtureProfileName,
                text: E2EHarness.testingCloneSourceText,
                vibe: .masc,
                voiceDescription: E2EHarness.testingProfileVoiceDescription,
                outputURL: referenceAudioURL,
            )

            try await E2EHarness.createCloneProfile(
                on: worker,
                id: testCase.createRequestID,
                profileName: testCase.profileName,
                referenceAudioURL: referenceAudioURL,
                vibe: testCase.vibe,
                transcript: E2EHarness.testingCloneSourceText,
                expectTranscription: false,
            )
        } else {
            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: testCase.createRequestID,
                profileName: testCase.profileName,
                text: E2EHarness.testingProfileText,
                vibe: testCase.vibe,
                voiceDescription: testCase.voiceDescription,
            )
        }

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: testCase.profileName)
        #expect(storedProfile.manifest.vibe == testCase.vibe)

        try await E2EHarness.runSilentSpeech(
            on: worker,
            id: testCase.liveRequestID,
            text: E2EHarness.testingPlaybackText,
            profileName: testCase.profileName,
        )
        try await E2EHarness.expectMarvisVoiceSelection(
            on: worker,
            requestID: testCase.liveRequestID,
            expectedVoice: testCase.expectedVoice,
        )

        if testCase == .femme {
            _ = try await E2EHarness.runGeneratedFileSpeech(
                on: worker,
                id: "req-file-marvis-femme",
                text: E2EHarness.testingPlaybackText,
                profileName: testCase.profileName,
            )
            try await E2EHarness.expectMarvisVoiceSelection(
                on: worker,
                requestID: "req-file-marvis-femme",
                expectedVoice: testCase.expectedVoice,
            )
        }

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test(.tags(.audible))
    func `audible playback across vibes`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
            speechBackend: .marvis,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)

        for lane in MarvisProfileLane.all {
            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: lane.createID,
                profileName: lane.profileName,
                text: E2EHarness.testingProfileText,
                vibe: lane.vibe,
                voiceDescription: lane.voiceDescription,
            )
        }

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        for lane in MarvisProfileLane.all {
            let storedProfile = try store.loadProfile(named: lane.profileName)
            #expect(storedProfile.manifest.vibe == lane.vibe)
        }

        for lane in MarvisProfileLane.all {
            try await E2EHarness.runAudibleSpeech(
                on: worker,
                id: lane.liveID,
                text: E2EHarness.testingPlaybackText,
                profileName: lane.profileName,
            )
            try await E2EHarness.expectMarvisVoiceSelection(
                on: worker,
                requestID: lane.liveID,
                expectedVoice: lane.expectedVoice,
            )
        }

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test(.tags(.audible))
    func `prequeued jobs drain in order`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let lanes = [
            MarvisProfileLane(
                createID: "req-create-marvis-queued-femme",
                liveID: "req-live-marvis-queued-femme",
                profileName: "marvis-queued-femme-profile",
                vibe: .femme,
                voiceDescription: "A warm, bright, feminine narrator voice.",
                expectedVoice: "conversational_a",
            ),
            MarvisProfileLane(
                createID: "req-create-marvis-queued-masc",
                liveID: "req-live-marvis-queued-masc",
                profileName: "marvis-queued-masc-profile",
                vibe: .masc,
                voiceDescription: "A grounded, rich, masculine speaking voice.",
                expectedVoice: "conversational_b",
            ),
            MarvisProfileLane(
                createID: "req-create-marvis-queued-androgenous",
                liveID: "req-live-marvis-queued-androgenous",
                profileName: "marvis-queued-androgenous-profile",
                vibe: .androgenous,
                voiceDescription: "A calm, balanced, and gentle speaking voice.",
                expectedVoice: "conversational_a",
            ),
        ]

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
            speechBackend: .marvis,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)

        for lane in lanes {
            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: lane.createID,
                profileName: lane.profileName,
                text: E2EHarness.testingProfileText,
                vibe: lane.vibe,
                voiceDescription: lane.voiceDescription,
            )
        }

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        for lane in lanes {
            let storedProfile = try store.loadProfile(named: lane.profileName)
            #expect(storedProfile.manifest.vibe == lane.vibe)
        }

        for lane in lanes {
            try await E2EHarness.queueAudibleSpeech(
                on: worker,
                id: lane.liveID,
                text: E2EHarness.testingPlaybackText,
                profileName: lane.profileName,
            )
        }

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == lanes[0].liveID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == lanes[1].liveID
                && $0["event"] as? String == "started"
        } != nil)

        let req1PrerollReadyIndex = worker.stdoutObjects().firstIndex { object in
            object["id"] as? String == lanes[0].liveID
                && object["event"] as? String == "progress"
                && object["stage"] as? String == "preroll_ready"
        }
        let req2StartedIndex = worker.stdoutObjects().firstIndex { object in
            object["id"] as? String == lanes[1].liveID
                && object["event"] as? String == "started"
        }

        #expect(req1PrerollReadyIndex != nil)
        #expect(req2StartedIndex != nil)
        if let req1PrerollReadyIndex, let req2StartedIndex {
            #expect(req1PrerollReadyIndex < req2StartedIndex)
        }

        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "marvis_generation_scheduler_snapshot",
                let details = $0["details"] as? [String: Any],
                let activeGenerationRequestIDs = details["active_generation_request_ids"] as? String,
                let activeMarvisGenerationLanes = details["active_marvis_generation_lanes"] as? String,
                let queuedGenerationRequestIDs = details["queued_generation_request_ids"] as? String,
                let parkedGenerationReasons = details["parked_generation_reasons"] as? String
            else {
                return false
            }

            return activeGenerationRequestIDs.contains(lanes[0].liveID)
                && !activeGenerationRequestIDs.contains(lanes[1].liveID)
                && activeMarvisGenerationLanes.contains("\(lanes[0].liveID):\(lanes[0].expectedVoice)")
                && queuedGenerationRequestIDs.contains(lanes[1].liveID)
                && parkedGenerationReasons.contains("\(lanes[1].liveID):waiting_for_playback_stability")
                && queuedGenerationRequestIDs.contains(lanes[2].liveID)
        } != nil)

        for lane in lanes {
            _ = try await E2EHarness.awaitAudibleSpeechCompletion(
                on: worker,
                id: lane.liveID,
            )
            try await E2EHarness.expectMarvisVoiceSelection(
                on: worker,
                requestID: lane.liveID,
                expectedVoice: lane.expectedVoice,
            )
        }

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
