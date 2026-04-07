import Foundation
import Testing
@testable import SpeakSwiftlyCore

@Suite(.serialized)
struct SpeakSwiftlyE2ETests {
    // MARK: Test Fixtures

    private static let testingProfileName = "testing-profile"
    private static let testingProfileText = "Hello there from SpeakSwiftly end-to-end coverage."
    private static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."
    private static let testingCloneSourceText = """
    This imported reference audio should let SpeakSwiftly build a clone profile for end to end coverage with a clean transcript and steady speech.
    """
    private static let testingPlaybackText = """
    Hello from the real resident SpeakSwiftly playback path. This end to end test now uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
    """
    private static let forensicPlaybackText = """
    Forensic playback probe begins now. Please read this exactly once and do not repeat yourself.
    The path `/Users/galew/Workspace/speak-to-user-mcp/src/speak_to_user_mcp/speakswiftly.py` contains a helper named `SpeakSwiftlyOwner.speak_live`.
    The config file `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should be spoken as plain speech rather than spiraling into code noise.
    Read this fenced code sample calmly.
    ```swift
    let sourcePath = "/Users/galew/Workspace/speak-to-user-mcp/src/speak_to_user_mcp/speakswiftly.py"
    let weirdWords = ["Xobni", "quizzaciously", "Cwmfjord", "phthalo", "lophophore"]
    let fallback = weirdWords.first(where: { $0.hasPrefix("q") }) ?? "nothing"
    print(sourcePath, fallback)
    ```
    Also read these oddly spelled words once each: quizzaciously, xylophonic, cwmfjord, lophophore, phthalo, zyzzyva.
    Finish with this sentence exactly once. End of forensic playback probe.
    """
    private static let segmentedForensicPlaybackText = """
    # Section One

    Please read this paragraph once and keep a natural tone. The path `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should sound like speech, not code noise.

    ## Section Two

    Read these symbol-heavy identifiers carefully: NSApplication.didFinishLaunchingNotification, AVAudioEngine.mainMixerNode, dot.syntax.stuff, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.

    ## Section Three

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    ## Section Four

    Also read these words once each: chrommmaticallly, qqqwweerrtyy, phthalo, zyzzyva, lophophore.

    ## Footer

    End this segmented forensic playback probe once, clearly, and without looping.
    """
    private static let reversedSegmentedForensicPlaybackText = """
    # Footer

    End this segmented forensic playback probe once, clearly, and without looping.

    ## Section Four

    Also read these words once each: chrommmaticallly, qqqwweerrtyy, phthalo, zyzzyva, lophophore.

    ## Section Three

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    ## Section Two

    Read these symbol-heavy identifiers carefully: NSApplication.didFinishLaunchingNotification, AVAudioEngine.mainMixerNode, dot.syntax.stuff, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.

    ## Section One

    Please read this paragraph once and keep a natural tone. The path `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should sound like speech, not code noise.
    """
    private static let segmentedConversationalPlaybackText = """
    # Section One

    Please read this opening section in a steady, friendly tone. We are checking how the worker sounds over a longer stretch of ordinary conversational prose, with enough breathing room and variety to make the trace useful instead of tiny and noisy.

    ## Section Two

    In this part, talk as if you are explaining a thoughtful idea to one person who is listening closely. Keep the pacing natural, let the phrasing stay connected, and avoid sounding clipped, rushed, or overly dramatic.

    ## Section Three

    Now continue with a calmer reflective paragraph about a quiet afternoon, a cup of tea, a patch of sun on the floor, and the feeling that time has slowed down just enough for the room to seem gentle and easy to inhabit.

    ## Section Four

    Finish the body with another plain spoken paragraph about wrapping up a task, setting the last page in order, and feeling relieved that the long careful effort has finally started to come together in a satisfying way.

    ## Footer

    End this conversational forensic playback probe once, clearly, and without looping.
    """
    private static let reversedSegmentedConversationalPlaybackText = """
    # Footer

    End this conversational forensic playback probe once, clearly, and without looping.

    ## Section Four

    Finish the body with another plain spoken paragraph about wrapping up a task, setting the last page in order, and feeling relieved that the long careful effort has finally started to come together in a satisfying way.

    ## Section Three

    Now continue with a calmer reflective paragraph about a quiet afternoon, a cup of tea, a patch of sun on the floor, and the feeling that time has slowed down just enough for the room to seem gentle and easy to inhabit.

    ## Section Two

    In this part, talk as if you are explaining a thoughtful idea to one person who is listening closely. Keep the pacing natural, let the phrasing stay connected, and avoid sounding clipped, rushed, or overly dramatic.

    ## Section One

    Please read this opening section in a steady, friendly tone. We are checking how the worker sounds over a longer stretch of ordinary conversational prose, with enough breathing room and variety to make the trace useful instead of tiny and noisy.
    """

    // MARK: Sequential End-to-End Workflows

    @Test func voiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "voice-design-profile"

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await Self.createVoiceDesignProfile(
                on: worker,
                id: "req-create-voice-design",
                profileName: profileName,
                text: Self.testingProfileText,
                voiceDescription: Self.testingProfileVoiceDescription
            )
            try await Self.runSilentSpeech(
                on: worker,
                id: "req-live-voice-design-silent",
                text: Self.testingPlaybackText,
                profileName: profileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: Self.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await Self.runAudibleSpeech(
                on: worker,
                id: "req-live-voice-design-audible",
                text: Self.testingPlaybackText,
                profileName: profileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }

    @Test func cloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "clone-source-profile"
        let cloneProfileName = "provided-transcript-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/provided-clone-reference.wav")

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await Self.createVoiceDesignProfile(
                on: worker,
                id: "req-create-clone-fixture",
                profileName: fixtureProfileName,
                text: Self.testingCloneSourceText,
                voiceDescription: Self.testingProfileVoiceDescription,
                outputURL: referenceAudioURL
            )
            #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

            try await Self.createCloneProfile(
                on: worker,
                id: "req-create-clone-provided-transcript",
                profileName: cloneProfileName,
                referenceAudioURL: referenceAudioURL,
                transcript: Self.testingCloneSourceText,
                expectTranscription: false
            )

            let store = ProfileStore(rootURL: sandbox.profileRootURL)
            let storedProfile = try store.loadProfile(named: cloneProfileName)
            #expect(storedProfile.manifest.sourceText == Self.testingCloneSourceText)

            try await Self.runSilentSpeech(
                on: worker,
                id: "req-live-clone-provided-transcript-silent",
                text: Self.testingPlaybackText,
                profileName: cloneProfileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: Self.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await Self.runAudibleSpeech(
                on: worker,
                id: "req-live-clone-provided-transcript-audible",
                text: Self.testingPlaybackText,
                profileName: cloneProfileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }

    @Test func cloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "inferred-clone-source-profile"
        let cloneProfileName = "inferred-transcript-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/inferred-clone-reference.wav")

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await Self.createVoiceDesignProfile(
                on: worker,
                id: "req-create-inferred-clone-fixture",
                profileName: fixtureProfileName,
                text: Self.testingCloneSourceText,
                voiceDescription: Self.testingProfileVoiceDescription,
                outputURL: referenceAudioURL
            )
            #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

            try await Self.createCloneProfile(
                on: worker,
                id: "req-create-clone-inferred-transcript",
                profileName: cloneProfileName,
                referenceAudioURL: referenceAudioURL,
                transcript: nil,
                expectTranscription: true
            )

            let store = ProfileStore(rootURL: sandbox.profileRootURL)
            let storedProfile = try store.loadProfile(named: cloneProfileName)
            let inferredTranscript = storedProfile.manifest.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!inferredTranscript.isEmpty)
            #expect(Self.transcriptLooksCloseToCloneSource(inferredTranscript))

            try await Self.runSilentSpeech(
                on: worker,
                id: "req-live-clone-inferred-transcript-silent",
                text: Self.testingPlaybackText,
                profileName: cloneProfileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: Self.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await Self.runAudibleSpeech(
                on: worker,
                id: "req-live-clone-inferred-transcript-audible",
                text: Self.testingPlaybackText,
                profileName: cloneProfileName
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }

    @Test func generatedFileLaneRunsEndToEndAndSupportsManagedArtifactReads() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: false)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-generated-file-profile",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        let generatedFile = try await Self.runGeneratedFileSpeech(
            on: worker,
            id: "req-generated-file-e2e",
            text: Self.testingPlaybackText,
            profileName: Self.testingProfileName
        )
        #expect(generatedFile["artifact_id"] as? String == "req-generated-file-e2e")
        #expect(generatedFile["profile_name"] as? String == Self.testingProfileName)

        let generatedFilePath = try #require(generatedFile["file_path"] as? String)
        #expect(FileManager.default.fileExists(atPath: generatedFilePath))

        try worker.sendJSON(
            """
            {"id":"req-generated-file-read","op":"generated_file","artifact_id":"req-generated-file-e2e"}
            """
        )

        let fetchedGeneratedFile = try #require(
            try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
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

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
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

    // MARK: Audible Playback and Tracing

    @Test func speakLivePlaybackTraceCanBeCapturedOnDemand() async throws {
        guard Self.isE2EEnabled, Self.isPlaybackTraceEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: true
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-trace",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-trace","op":"queue_speech_live","text":"\(Self.testingPlaybackText)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "playback_trace_chunk_received"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "playback_trace_buffer_scheduled"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "playback_trace_buffer_played_back"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-trace"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    // MARK: Forensic Playback Probes

    @Test func forensicSpeakLiveRunsEndToEndWithLongCodeHeavyRequest() async throws {
        guard Self.isE2EEnabled, Self.isForensicE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-forensic",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-forensic","op":"queue_speech_live","text":"\(Self.forensicPlaybackText.jsonEscaped)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-forensic"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-forensic"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-forensic",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return details["chunk_count"] as? Int != nil
                    && details["sample_count"] as? Int != nil
                    && details["time_to_first_chunk_ms"] as? Int != nil
                    && details["time_to_preroll_ready_ms"] as? Int != nil
                    && details["schedule_callback_count"] as? Int != nil
                    && details["played_back_callback_count"] as? Int != nil
            }
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["chunk_count"] as? Int ?? 0) > 1)
        #expect((playbackDetails["sample_count"] as? Int ?? 0) > 0)

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-forensic"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func forensicSpeakLiveRunsEndToEndWithSegmentedWeirdTextRequest() async throws {
        guard Self.isE2EEnabled, Self.isForensicE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-segmented",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-segmented","op":"queue_speech_live","text":"\(Self.segmentedForensicPlaybackText.jsonEscaped)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-segmented"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-segmented",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["url_count"] as? Int ?? 0) >= 1
                    && (details["file_path_count"] as? Int ?? 0) >= 1
                    && (details["dotted_identifier_count"] as? Int ?? 0) >= 2
                    && (details["camel_case_token_count"] as? Int ?? 0) >= 1
                    && (details["snake_case_token_count"] as? Int ?? 0) >= 1
                    && (details["objc_symbol_count"] as? Int ?? 0) >= 1
                    && (details["repeated_letter_run_count"] as? Int ?? 0) >= 2
            }
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-segmented",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Section Two"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-segmented"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func forensicSpeakLiveRunsEndToEndWithReversedSegmentedWeirdTextRequest() async throws {
        guard Self.isE2EEnabled, Self.isForensicE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-reversed-segmented",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-reversed-segmented","op":"queue_speech_live","text":"\(Self.reversedSegmentedForensicPlaybackText.jsonEscaped)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-segmented"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-reversed-segmented",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["url_count"] as? Int ?? 0) >= 1
                    && (details["file_path_count"] as? Int ?? 0) >= 1
                    && (details["dotted_identifier_count"] as? Int ?? 0) >= 2
                    && (details["camel_case_token_count"] as? Int ?? 0) >= 1
                    && (details["snake_case_token_count"] as? Int ?? 0) >= 1
                    && (details["objc_symbol_count"] as? Int ?? 0) >= 1
                    && (details["repeated_letter_run_count"] as? Int ?? 0) >= 2
            }
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-reversed-segmented",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Footer"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-segmented"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func forensicSpeakLiveRunsEndToEndWithSegmentedConversationalProseRequest() async throws {
        guard Self.isE2EEnabled, Self.isForensicE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-conversational",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-conversational","op":"queue_speech_live","text":"\(Self.segmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-conversational"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-conversational",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["file_path_count"] as? Int ?? 0) == 0
                    && (details["dotted_identifier_count"] as? Int ?? 0) == 0
                    && (details["camel_case_token_count"] as? Int ?? 0) == 0
                    && (details["snake_case_token_count"] as? Int ?? 0) == 0
                    && (details["objc_symbol_count"] as? Int ?? 0) == 0
                    && (details["repeated_letter_run_count"] as? Int ?? 0) == 0
            }
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-conversational",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Section Two"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-conversational"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func forensicSpeakLiveRunsEndToEndWithReversedSegmentedConversationalProseRequest() async throws {
        guard Self.isE2EEnabled, Self.isForensicE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )
        defer { Task { await worker.stop() } }

        try await Self.awaitWorkerReady(worker, expectPlaybackEngine: true)
        try await Self.createVoiceDesignProfile(
            on: worker,
            id: "req-create-reversed-conversational",
            profileName: Self.testingProfileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        try worker.sendJSON(
            """
            {"id":"req-live-reversed-conversational","op":"queue_speech_live","text":"\(Self.reversedSegmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-conversational"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-reversed-conversational",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["file_path_count"] as? Int ?? 0) == 0
                    && (details["dotted_identifier_count"] as? Int ?? 0) == 0
                    && (details["camel_case_token_count"] as? Int ?? 0) == 0
                    && (details["snake_case_token_count"] as? Int ?? 0) == 0
                    && (details["objc_symbol_count"] as? Int ?? 0) == 0
                    && (details["repeated_letter_run_count"] as? Int ?? 0) == 0
            }
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-reversed-conversational",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Footer"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-conversational"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    // MARK: Workflow Helpers

    private static func awaitWorkerReady(
        _ worker: WorkerProcess,
        expectPlaybackEngine: Bool
    ) async throws {
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } != nil)

        guard expectPlaybackEngine else { return }

        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_phys_footprint_bytes"] as? Int != nil
                && details["process_resident_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
                && details["mlx_cache_memory_bytes"] as? Int != nil
                && details["mlx_peak_memory_bytes"] as? Int != nil
        } != nil)
    }

    private static func createVoiceDesignProfile(
        on worker: WorkerProcess,
        id: String,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputURL: URL? = nil
    ) async throws {
        if let outputURL {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let outputPathFragment = outputURL.map { #","output_path":"\#($0.path)""# } ?? ""
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"create_profile","profile_name":"\(profileName)","text":"\(text.jsonEscaped)","voice_description":"\(voiceDescription.jsonEscaped)"\(outputPathFragment)}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "loading_profile_model"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_profile_audio"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                $0["id"] as? String == id
                    && $0["ok"] as? Bool == true
            }
        )

        #expect(success["profile_name"] as? String == profileName)
        if let outputURL {
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    private static func createCloneProfile(
        on worker: WorkerProcess,
        id: String,
        profileName: String,
        referenceAudioURL: URL,
        transcript: String?,
        expectTranscription: Bool
    ) async throws {
        let transcriptFragment = transcript.map { #","transcript":"\#($0.jsonEscaped)""# } ?? ""
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"create_clone","profile_name":"\(profileName)","reference_audio_path":"\(referenceAudioURL.path)"\(transcriptFragment)}
            """
        )

        if expectTranscription {
            #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                $0["id"] as? String == id
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "loading_clone_transcription_model"
            } != nil)
            #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                $0["id"] as? String == id
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "transcribing_clone_audio"
            } != nil)
        }

        let success = try #require(
            try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                $0["id"] as? String == id
                    && $0["ok"] as? Bool == true
            }
        )

        #expect(success["profile_name"] as? String == profileName)
    }

    private static func runSilentSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String
    ) async throws {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"queue_speech_live","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
        } != nil)
    }

    private static func runAudibleSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String
    ) async throws {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"queue_speech_live","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_started",
                $0["request_id"] as? String == id,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String

            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && (details["startup_buffer_target_ms"] as? Int ?? 0) >= 360
                && details["startup_buffered_audio_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["process_resident_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
                && details["mlx_cache_memory_bytes"] as? Int != nil
                && details["mlx_peak_memory_bytes"] as? Int != nil
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == id,
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                let textComplexityClass = details["text_complexity_class"] as? String

                return ["compact", "balanced", "extended"].contains(textComplexityClass)
                    && (details["startup_buffer_target_ms"] as? Int ?? 0) >= 360
                    && (details["low_water_target_ms"] as? Int ?? 0) >= 140
                    && (details["resume_buffer_target_ms"] as? Int ?? 0) >= (details["startup_buffer_target_ms"] as? Int ?? 0)
                    && (details["chunk_gap_warning_threshold_ms"] as? Int ?? 0) >= 360
                    && (details["schedule_gap_warning_threshold_ms"] as? Int ?? 0) >= 140
                    && details["startup_buffered_audio_ms"] as? Int != nil
                    && details["min_queued_audio_ms"] as? Int != nil
                    && details["max_queued_audio_ms"] as? Int != nil
                    && details["avg_queued_audio_ms"] as? Int != nil
                    && details["queue_depth_sample_count"] as? Int != nil
                    && details["schedule_callback_count"] as? Int != nil
                    && details["played_back_callback_count"] as? Int != nil
                    && details["fade_in_chunk_count"] as? Int != nil
                    && details["starvation_event_count"] as? Int != nil
                    && details["process_phys_footprint_bytes"] as? Int != nil
                    && details["process_resident_bytes"] as? Int != nil
                    && details["mlx_active_memory_bytes"] as? Int != nil
                    && details["mlx_cache_memory_bytes"] as? Int != nil
                    && details["mlx_peak_memory_bytes"] as? Int != nil
            }
        )

        #expect(playbackFinished["event"] as? String == "playback_finished")
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
        } != nil)
    }

    private static func runGeneratedFileSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String
    ) async throws -> [String: Any] {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"queue_speech_file","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
                && $0["generated_file"] == nil
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_file"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_file_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "writing_generated_file"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                guard
                    $0["id"] as? String == id,
                    $0["ok"] as? Bool == true,
                    let generatedFile = $0["generated_file"] as? [String: Any]
                else {
                    return false
                }

                return generatedFile["artifact_id"] as? String == id
            }
        )

        return try #require(success["generated_file"] as? [String: Any])
    }

    private static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
        let expectedTokens = normalizedTranscriptTokens(from: Self.testingCloneSourceText)
        let actualTokens = normalizedTranscriptTokens(from: transcript)

        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else {
            return false
        }

        let sharedTokens = expectedTokens.intersection(actualTokens)
        let recall = Double(sharedTokens.count) / Double(expectedTokens.count)
        let precision = Double(sharedTokens.count) / Double(actualTokens.count)

        return recall >= 0.7 && precision >= 0.6
    }

    private static func normalizedTranscriptTokens(from text: String) -> Set<String> {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return Set(
            normalized
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    private static var e2eTimeout: Duration {
        .seconds(1_200)
    }

    private static var isE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_E2E"] == "1"
    }

    private static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    private static var isForensicE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_FORENSIC_E2E"] == "1"
    }
}

private struct E2ESandbox {
    let rootURL: URL
    let profileRootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftly-E2E-\(UUID().uuidString)", isDirectory: true)
        profileRootURL = rootURL.appendingPathComponent("profiles", isDirectory: true)

        try FileManager.default.createDirectory(at: profileRootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private final class JSONLineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutObjects = [[String: Any]]()
    private var stderrObjects = [[String: Any]]()
    private var stderrLines = [String]()

    func appendStdout(_ line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        lock.withLock {
            stdoutObjects.append(object)
        }
    }

    func appendStderr(_ line: String) {
        lock.withLock {
            stderrLines.append(line)
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }

            stderrObjects.append(object)
        }
    }

    func firstMatchingJSONObject(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.withLock {
            stdoutObjects.first(where: predicate)
        }
    }

    func stderrText() -> String {
        lock.withLock {
            stderrLines.joined(separator: "\n")
        }
    }

    func firstMatchingStderrJSONObject(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.withLock {
            stderrObjects.first(where: predicate)
        }
    }
}

private final class WorkerProcess: @unchecked Sendable {
    private enum Environment {
        static let dyldFrameworkPath = "DYLD_FRAMEWORK_PATH"
        static let profileRoot = "SPEAKSWIFTLY_PROFILE_ROOT"
        static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
        static let playbackTrace = "SPEAKSWIFTLY_PLAYBACK_TRACE"
    }

    private static let executableURLResult = Result(catching: {
        try computeWorkerExecutableURL()
    })

    private let process: Process
    private let stdinPipe: Pipe
    private let recorder: JSONLineRecorder
    private let stdoutTask: Task<Void, Never>
    private let stderrTask: Task<Void, Never>

    init(profileRootURL: URL, silentPlayback: Bool, playbackTrace: Bool = false) throws {
        process = Process()
        stdinPipe = Pipe()
        let recorder = JSONLineRecorder()
        self.recorder = recorder
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let executableURL = try Self.workerExecutableURL()
        process.executableURL = executableURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment[Environment.dyldFrameworkPath] = executableURL.deletingLastPathComponent().path
        environment[Environment.profileRoot] = profileRootURL.path
        if silentPlayback {
            environment[Environment.silentPlayback] = "1"
        }
        if playbackTrace {
            environment[Environment.playbackTrace] = "1"
        }
        process.environment = environment

        stdoutTask = Self.captureLines(
            from: stdoutPipe.fileHandleForReading,
            append: recorder.appendStdout(_:)
        )

        stderrTask = Self.captureLines(
            from: stderrPipe.fileHandleForReading,
            append: recorder.appendStderr(_:)
        )

        try process.run()
    }

    deinit {
        stdoutTask.cancel()
        stderrTask.cancel()
    }

    func sendJSON(_ jsonLine: String) throws {
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data((jsonLine + "\n").utf8))
    }

    func closeInput() throws {
        try stdinPipe.fileHandleForWriting.close()
    }

    func stop() async {
        if process.isRunning {
            try? closeInput()
            try? await waitForExit(timeout: .seconds(5))
        }

        if process.isRunning {
            process.terminate()
            try? await waitForExit(timeout: .seconds(5))
        }

        stdoutTask.cancel()
        stderrTask.cancel()
    }

    func waitForJSONObject(
        timeout: Duration,
        _ predicate: @escaping @Sendable ([String: Any]) -> Bool
    ) async throws -> [String: Any]? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if let object = recorder.firstMatchingJSONObject(predicate) {
                return object
            }

            if !process.isRunning {
                break
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        if let object = recorder.firstMatchingJSONObject(predicate) {
            return object
        }

        let stderr = recorder.stderrText()
        throw WorkerProcessError(
            "Timed out waiting for a matching worker JSON event. Current stderr:\n\(stderr)"
        )
    }

    func waitForExit(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while process.isRunning && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }

        guard !process.isRunning else {
            let stderr = recorder.stderrText()
            throw WorkerProcessError(
                "The SpeakSwiftly worker did not exit before the timeout expired. Current stderr:\n\(stderr)"
            )
        }

        guard process.terminationStatus == 0 else {
            let stderr = recorder.stderrText()
            throw WorkerProcessError(
                "The SpeakSwiftly worker exited with status \(process.terminationStatus). Current stderr:\n\(stderr)"
            )
        }
    }

    func waitForStderrJSONObject(
        timeout: Duration,
        _ predicate: @escaping @Sendable ([String: Any]) -> Bool
    ) async throws -> [String: Any]? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if let object = recorder.firstMatchingStderrJSONObject(predicate) {
                return object
            }

            if !process.isRunning {
                break
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        if let object = recorder.firstMatchingStderrJSONObject(predicate) {
            return object
        }

        let stderr = recorder.stderrText()
        throw WorkerProcessError(
            "Timed out waiting for a matching worker stderr JSON event. Current stderr:\n\(stderr)"
        )
    }

    private static func captureLines(
        from fileHandle: FileHandle,
        append: @escaping @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            var buffer = Data()

            while !Task.isCancelled {
                let data = fileHandle.availableData
                guard !data.isEmpty else { break }
                buffer.append(data)

                while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer[..<newlineRange.lowerBound]
                    if let line = String(data: lineData, encoding: .utf8) {
                        append(line)
                    }
                    buffer.removeSubrange(..<newlineRange.upperBound)
                }
            }

            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                append(line)
            }
        }
    }

    private static func workerExecutableURL() throws -> URL {
        try executableURLResult.get()
    }

    private static func computeWorkerExecutableURL() throws -> URL {
        let packageRootURL = try packageRootURL()
        try publishWorkerRuntime(packageRootURL: packageRootURL, configuration: "Debug")

        let productsURL = packageRootURL
            .appendingPathComponent(".local/xcode/Debug", isDirectory: true)
        let executableURL = productsURL.appendingPathComponent("SpeakSwiftly", isDirectory: false)
        let metallibURL = productsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw WorkerProcessError(
                "The Xcode-built SpeakSwiftly worker was expected at '\(executableURL.path)', but no executable was found after `xcodebuild` finished."
            )
        }

        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw WorkerProcessError(
                "The MLX Metal shader bundle was not found at '\(metallibURL.path)' after `xcodebuild` completed. The worker cannot run real MLX-backed e2e tests without `default.metallib`."
            )
        }

        return executableURL
    }

    private static func packageRootURL() throws -> URL {
        let fileManager = FileManager.default
        var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let manifestURL = candidateURL.appendingPathComponent("Package.swift", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL != candidateURL else {
                throw WorkerProcessError(
                    "SpeakSwiftly e2e tests could not find the package root while walking upward from '\(#filePath)'. Expected to find a directory containing 'Package.swift'."
                )
            }

            candidateURL = parentURL
        }
    }

    private static func buildWorkerProduct(
        packageRootURL: URL,
        configuration: String
    ) throws {
        let process = Process()
        let logURL = packageRootURL
            .appendingPathComponent(".local/xcode/SpeakSwiftly-e2e-publish-\(configuration.lowercased()).log", isDirectory: false)
        try FileManager.default.createDirectory(
            at: packageRootURL.appendingPathComponent(".local/xcode", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        process.currentDirectoryURL = packageRootURL
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "scripts/repo-maintenance/publish-runtime.sh",
            "--configuration", configuration,
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = try Data(contentsOf: logURL)
            let output = String(decoding: outputData, as: UTF8.self)
            throw WorkerProcessError(
                "The SpeakSwiftly runtime publisher failed with status \(process.terminationStatus). Publisher output:\n\(output)"
            )
        }
    }

    private static func publishWorkerRuntime(
        packageRootURL: URL,
        configuration: String
    ) throws {
        try buildWorkerProduct(
            packageRootURL: packageRootURL,
            configuration: configuration
        )
    }
}

private struct WorkerProcessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension String {
    var jsonEscaped: String {
        let data = (try? JSONSerialization.data(withJSONObject: [self])) ?? Data("[\"\"]".utf8)
        let encoded = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst(2).dropLast(2))
    }
}
