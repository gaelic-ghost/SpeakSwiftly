#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

enum MarvisRouteCase: String, CaseIterable {
    case femme
    case mascClone
    case femmeAlternate

    var profileName: String {
        switch self {
            case .femme:
                "marvis-femme-profile"
            case .mascClone:
                "marvis-masc-clone-profile"
            case .femmeAlternate:
                "marvis-femme-alt-profile"
        }
    }

    var liveRequestID: String {
        switch self {
            case .femme:
                "req-live-marvis-femme"
            case .mascClone:
                "req-live-marvis-masc"
            case .femmeAlternate:
                "req-live-marvis-femme-alt"
        }
    }

    var vibe: SpeakSwiftly.Vibe {
        switch self {
            case .femme:
                .femme
            case .mascClone:
                .masc
            case .femmeAlternate:
                .femme
        }
    }

    var fixture: E2EProfileFixture {
        switch self {
            case .femme, .femmeAlternate:
                .femmeDesign
            case .mascClone:
                .mascCloneProvided
        }
    }

    var expectedVoice: String {
        switch self {
            case .mascClone:
                "conversational_b"
            case .femme, .femmeAlternate:
                "conversational_a"
        }
    }
}

private struct MarvisProfileLane {
    let liveID: String
    let profileName: String
    let vibe: SpeakSwiftly.Vibe
    let expectedVoice: String
    let fixture: E2EProfileFixture

    static let all: [Self] = [
        Self(
            liveID: "req-live-marvis-triplet-femme",
            profileName: "marvis-triplet-femme-profile",
            vibe: .femme,
            expectedVoice: "conversational_a",
            fixture: .femmeDesign,
        ),
        Self(
            liveID: "req-live-marvis-triplet-masc",
            profileName: "marvis-triplet-masc-profile",
            vibe: .masc,
            expectedVoice: "conversational_b",
            fixture: .mascDesign,
        ),
        Self(
            liveID: "req-live-marvis-triplet-femme-alt",
            profileName: "marvis-triplet-femme-alt-profile",
            vibe: .femme,
            expectedVoice: "conversational_a",
            fixture: .femmeDesign,
        ),
    ]
}

@Suite(
    .serialized,
    .tags(.e2e, .marvis),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct MarvisE2ETests {
    @Test(arguments: MarvisRouteCase.allCases)
    func `routes expected conversational voice`(testCase: MarvisRouteCase) async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .marvis,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(testCase.fixture, as: testCase.profileName)

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
            try sandbox.seedProfileFixture(lane.fixture, as: lane.profileName)
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
    func `queued audible playback stays serialized and routes expected voices`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let lanes = [
            MarvisProfileLane(
                liveID: "req-live-marvis-queued-femme",
                profileName: "marvis-queued-femme-profile",
                vibe: .femme,
                expectedVoice: "conversational_a",
                fixture: .femmeDesign,
            ),
            MarvisProfileLane(
                liveID: "req-live-marvis-queued-masc",
                profileName: "marvis-queued-masc-profile",
                vibe: .masc,
                expectedVoice: "conversational_b",
                fixture: .mascDesign,
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
            try sandbox.seedProfileFixture(lane.fixture, as: lane.profileName)
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
                && $0["event"] as? String == "queued"
                && (($0["reason"] as? String == "waiting_for_playback_stability")
                    || ($0["reason"] as? String == "waiting_for_active_request"))
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
