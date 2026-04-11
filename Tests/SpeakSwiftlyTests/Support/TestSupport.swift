import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Locking Helpers

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - Output Capture

final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutLines = [String]()
    private var stderrLines = [String]()

    func writeStdout(_ data: Data) throws {
        let string = String(decoding: data, as: UTF8.self)
        let lines = string
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        lock.withLock {
            stdoutLines.append(contentsOf: lines)
        }
    }

    func writeStderr(_ message: String) {
        lock.withLock {
            stderrLines.append(message)
        }
    }

    func containsJSONObject(_ predicate: ([String: Any]) -> Bool) -> Bool {
        lock.withLock {
            stdoutLines.contains { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                else {
                    return false
                }

                return predicate(object)
            }
        }
    }

    func countJSONObjects(_ predicate: ([String: Any]) -> Bool) -> Int {
        lock.withLock {
            stdoutLines.reduce(into: 0) { count, line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    predicate(object)
                else {
                    return
                }

                count += 1
            }
        }
    }

    func containsStderrJSONObject(_ predicate: ([String: Any]) -> Bool) -> Bool {
        lock.withLock {
            stderrLines.contains { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                else {
                    return false
                }

                return predicate(object)
            }
        }
    }

    func stdoutJSONObjects() -> [[String: Any]] {
        lock.withLock {
            stdoutLines.compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        }
    }

    func stderrJSONObjects() -> [[String: Any]] {
        lock.withLock {
            stderrLines.compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        }
    }

    func firstStdoutJSONObjectIndex(_ predicate: ([String: Any]) -> Bool) -> Int? {
        lock.withLock {
            stdoutLines.firstIndex { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                else {
                    return false
                }

                return predicate(object)
            }
        }
    }

    func startedEvents() -> [String] {
        lock.withLock {
            stdoutLines.compactMap { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    object["event"] as? String == "started",
                    let id = object["id"] as? String,
                    let op = object["op"] as? String
                else {
                    return nil
                }

                return "\(id):\(op)"
            }
        }
    }
}

// MARK: - Async Coordination

actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Playback Spies

final class PlaybackSpy: @unchecked Sendable {
    enum Behavior: Sendable {
        case immediate
        case gate(AsyncGate)
        case sleep(Duration)
        case emitLowQueueThenStarve
        case emitObservabilityBurst
        case `throw`(WorkerError)
    }

    private let lock = NSLock()
    private let behavior: Behavior
    private let environmentEvents: [PlaybackEnvironmentEvent]
    private(set) var playCount = 0
    private(set) var prepareCount = 0
    private(set) var stopCount = 0

    init(
        behavior: Behavior = .immediate,
        environmentEvents: [PlaybackEnvironmentEvent] = []
    ) {
        self.behavior = behavior
        self.environmentEvents = environmentEvents
    }

    func controller() -> AnyPlaybackController {
        AnyPlaybackController(
            prepare: { [self] _ in
                lock.withLock { prepareCount += 1 }
                return prepareCount == 1
            },
            play: { [self] _, text, stream, onEvent in
                lock.withLock { playCount += 1 }
                let thresholds = PlaybackThresholdController(text: text).thresholds

                var emittedFirstChunk = false
                var emittedPrerollReady = false
                var chunkCount = 0
                var sampleCount = 0
                var startupBufferedAudioMS: Int?
                var minQueuedAudioMS: Int?
                var maxQueuedAudioMS: Int?
                var queueDepthTotalMS = 0
                var queueDepthSampleCount = 0
                var rebufferEventCount = 0
                var starvationEventCount = 0
                var pendingSampleCount = 0
                var maxInterChunkGapMS: Int?
                var avgInterChunkGapMS: Int?
                var maxScheduleGapMS: Int?
                var avgScheduleGapMS: Int?
                var maxBoundaryDiscontinuity: Double?
                var maxLeadingAbsAmplitude: Double?
                var maxTrailingAbsAmplitude: Double?
                var fadeInChunkCount = 0
                var rebufferTotalDurationMS = 0
                var longestRebufferDurationMS = 0
                var scheduleCallbackCount = 0
                var playedBackCallbackCount = 0

                func bufferedAudioMS() -> Int {
                    Int((Double(pendingSampleCount) / 24_000.0 * 1_000).rounded())
                }

                func recordQueueDepth() {
                    let queuedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = min(minQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    maxQueuedAudioMS = max(maxQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    queueDepthTotalMS += queuedAudioMS
                    queueDepthSampleCount += 1
                }

                for try await (chunkIndex, chunk) in [Float].asyncEnumerated(stream) {
                    guard !chunk.isEmpty else { continue }
                    chunkCount += 1
                    sampleCount += chunk.count
                    pendingSampleCount += chunk.count
                    scheduleCallbackCount += 1
                    playedBackCallbackCount += 1
                    recordQueueDepth()

                    if let firstSample = chunk.first, let lastSample = chunk.last {
                        let leadingAbs = Double(abs(firstSample))
                        let trailingAbs = Double(abs(lastSample))
                        maxLeadingAbsAmplitude = max(maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
                        maxTrailingAbsAmplitude = max(maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
                        if chunkIndex > 0 {
                            let jump = Double(abs(firstSample - (Float(chunkIndex) / 10 + 0.1)))
                            maxBoundaryDiscontinuity = max(maxBoundaryDiscontinuity ?? jump, jump)
                        }
                    }

                    if !emittedFirstChunk {
                        emittedFirstChunk = true
                        fadeInChunkCount = 1
                        await onEvent(.firstChunk)
                    }

                    if !emittedPrerollReady, bufferedAudioMS() >= thresholds.startupBufferTargetMS {
                        emittedPrerollReady = true
                        startupBufferedAudioMS = bufferedAudioMS()
                        minQueuedAudioMS = startupBufferedAudioMS
                        await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
                    }
                }

                if !emittedPrerollReady, pendingSampleCount > 0 {
                    emittedPrerollReady = true
                    startupBufferedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = startupBufferedAudioMS
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
                }

                switch behavior {
                case .immediate:
                    break
                case .gate(let drainGate):
                    await drainGate.wait()
                case .sleep(let duration):
                    try await Task.sleep(for: duration)
                case .emitLowQueueThenStarve:
                    await onEvent(.rebufferStarted(queuedAudioMS: 120, thresholds: thresholds))
                    await onEvent(.rebufferResumed(bufferedAudioMS: 320, thresholds: thresholds))
                    rebufferEventCount = 1
                    rebufferTotalDurationMS = 90
                    longestRebufferDurationMS = 90
                    await onEvent(.queueDepthLow(queuedAudioMS: 50))
                    await onEvent(.starved)
                    starvationEventCount = 1
                    minQueuedAudioMS = 0
                    maxQueuedAudioMS = max(maxQueuedAudioMS ?? 320, 320)
                    maxInterChunkGapMS = 510
                    avgInterChunkGapMS = 510
                    maxScheduleGapMS = 220
                    avgScheduleGapMS = 220
                case .emitObservabilityBurst:
                    await onEvent(.chunkGapWarning(gapMS: 520, chunkIndex: 2))
                    await onEvent(.scheduleGapWarning(gapMS: 210, bufferIndex: 2, queuedAudioMS: 140))
                    await onEvent(.rebufferStarted(queuedAudioMS: 90, thresholds: thresholds))
                    await onEvent(.rebufferResumed(bufferedAudioMS: 340, thresholds: thresholds))
                    await onEvent(.rebufferThrashWarning(rebufferEventCount: 3, windowMS: 2_000))
                    await onEvent(
                        .bufferShapeSummary(
                            maxBoundaryDiscontinuity: 0.42,
                            maxLeadingAbsAmplitude: 0.31,
                            maxTrailingAbsAmplitude: 0.37,
                            fadeInChunkCount: 1
                        )
                    )
                    await onEvent(
                        .trace(
                            PlaybackTraceEvent(
                                name: "chunk_received",
                                chunkIndex: 1,
                                bufferIndex: nil,
                                sampleCount: 9_600,
                                durationMS: 400,
                                queuedAudioBeforeMS: 0,
                                queuedAudioAfterMS: 400,
                                gapMS: nil,
                                isRebuffering: false,
                                fadeInApplied: true
                            )
                        )
                    )
                    await onEvent(
                        .trace(
                            PlaybackTraceEvent(
                                name: "buffer_scheduled",
                                chunkIndex: 1,
                                bufferIndex: 1,
                                sampleCount: 9_600,
                                durationMS: 400,
                                queuedAudioBeforeMS: 0,
                                queuedAudioAfterMS: 400,
                                gapMS: nil,
                                isRebuffering: false,
                                fadeInApplied: true
                            )
                        )
                    )
                    rebufferEventCount = 3
                    rebufferTotalDurationMS = 180
                    longestRebufferDurationMS = 80
                    minQueuedAudioMS = 90
                    maxQueuedAudioMS = 400
                    maxInterChunkGapMS = 520
                    avgInterChunkGapMS = 410
                    maxScheduleGapMS = 210
                    avgScheduleGapMS = 155
                    maxBoundaryDiscontinuity = 0.42
                    maxLeadingAbsAmplitude = 0.31
                    maxTrailingAbsAmplitude = 0.37
                    fadeInChunkCount = 1
                case .throw(let error):
                    throw error
                }

                return PlaybackSummary(
                    thresholds: thresholds,
                    chunkCount: chunkCount,
                    sampleCount: sampleCount,
                    startupBufferedAudioMS: startupBufferedAudioMS,
                    timeToFirstChunkMS: emittedFirstChunk ? 0 : nil,
                    timeToPrerollReadyMS: emittedPrerollReady ? 0 : nil,
                    timeFromPrerollReadyToDrainMS: emittedPrerollReady ? 0 : nil,
                    minQueuedAudioMS: minQueuedAudioMS,
                    maxQueuedAudioMS: maxQueuedAudioMS,
                    avgQueuedAudioMS: queueDepthSampleCount == 0 ? nil : queueDepthTotalMS / queueDepthSampleCount,
                    queueDepthSampleCount: queueDepthSampleCount,
                    rebufferEventCount: rebufferEventCount,
                    rebufferTotalDurationMS: rebufferTotalDurationMS,
                    longestRebufferDurationMS: longestRebufferDurationMS,
                    starvationEventCount: starvationEventCount,
                    scheduleCallbackCount: scheduleCallbackCount,
                    playedBackCallbackCount: playedBackCallbackCount,
                    maxInterChunkGapMS: maxInterChunkGapMS,
                    avgInterChunkGapMS: avgInterChunkGapMS,
                    maxScheduleGapMS: maxScheduleGapMS,
                    avgScheduleGapMS: avgScheduleGapMS,
                    maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                    maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                    maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                    fadeInChunkCount: fadeInChunkCount
                )
            },
            stop: { [self] in
                lock.withLock { stopCount += 1 }
            },
            pause: { .paused },
            resume: { .playing },
            state: { .idle },
            bindEnvironmentEvents: { [environmentEvents] sink in
                guard let sink else { return }
                for event in environmentEvents {
                    await sink(event)
                }
            }
        )
    }
}

// MARK: - Model Recorders

final class ResidentModelRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lastText: String?
    private(set) var lastVoice: String?
    private(set) var lastRefText: String?
    private(set) var lastRefAudioWasProvided = false
    private(set) var audioLoadCallCount = 0
    private(set) var lastGenerationParameters: GenerateParameters?

    func record(
        text: String,
        voice: String?,
        refAudioWasProvided: Bool,
        refText: String?,
        generationParameters: GenerateParameters
    ) {
        lock.withLock {
            lastText = text
            lastVoice = voice
            lastRefAudioWasProvided = refAudioWasProvided
            lastRefText = refText
            lastGenerationParameters = generationParameters
        }
    }

    func recordAudioLoad() {
        lock.withLock {
            audioLoadCallCount += 1
        }
    }
}

// MARK: - Test Model and Runtime Factories

func makeResidentModel(recorder: ResidentModelRecorder? = nil, chunkCount: Int = 1) -> AnySpeechModel {
    AnySpeechModel(
        sampleRate: 24_000,
        generate: { _, _, _, _, _, _ in
            [0.1, 0.2]
        },
        generateSamplesStream: { text, voice, refAudio, refText, _, generationParameters, _ in
            recorder?.record(
                text: text,
                voice: voice,
                refAudioWasProvided: refAudio != nil,
                refText: refText,
                generationParameters: generationParameters
            )

            return AsyncThrowingStream { continuation in
                for chunkIndex in 0..<chunkCount {
                    let base = Float(chunkIndex + 1) / 10
                    continuation.yield([base, base + 0.1])
                }
                continuation.finish()
            }
        },
        generateEventStream: { text, voice, refAudio, refText, _, generationParameters, _ in
            recorder?.record(
                text: text,
                voice: voice,
                refAudioWasProvided: refAudio != nil,
                refText: refText,
                generationParameters: generationParameters
            )

            return AsyncThrowingStream { continuation in
                continuation.yield(.token(101))
                continuation.yield(
                    .info(
                        .init(
                            promptTokenCount: 12,
                            generationTokenCount: chunkCount * 4,
                            prefillTime: 0.12,
                            generateTime: 0.34,
                            tokensPerSecond: 56.7,
                            peakMemoryUsage: 1.23
                        )
                    )
                )
                for chunkIndex in 0..<chunkCount {
                    let base = Float(chunkIndex + 1) / 10
                    continuation.yield(.audio([base, base + 0.1]))
                }
                continuation.finish()
            }
        }
    )
}

func makeResidentModels(
    for backend: SpeakSwiftly.SpeechBackend,
    recorder: ResidentModelRecorder? = nil,
    chunkCount: Int = 1
) -> ResidentSpeechModels {
    switch backend {
    case .qwen3, .qwen3CustomVoice:
        .qwen3(makeResidentModel(recorder: recorder, chunkCount: chunkCount))
    case .marvis:
        .marvis(
            MarvisResidentModels(
                conversationalA: makeResidentModel(recorder: recorder, chunkCount: chunkCount),
                conversationalB: makeResidentModel(recorder: recorder, chunkCount: chunkCount)
            )
        )
    }
}

func makeProfileModel(waitBeforeGenerate: (@Sendable () async -> Void)? = nil) -> AnySpeechModel {
    AnySpeechModel(
        sampleRate: 24_000,
        generate: { _, _, _, _, _, _ in
            if let waitBeforeGenerate {
                await waitBeforeGenerate()
            }
            return [0.1, 0.2, 0.3]
        },
        generateSamplesStream: { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    )
}

func makeCloneTranscriptionModel(
    transcript: String = "Inferred transcript from reference audio."
) -> AnyCloneTranscriptionModel {
    AnyCloneTranscriptionModel(
        sampleRate: ModelFactory.cloneTranscriptionSampleRate,
        transcribe: { _, _ in transcript }
    )
}

func makeProfileStore(rootURL: URL) throws -> ProfileStore {
    let store = ProfileStore(rootURL: rootURL, fileManager: .default)
    try store.ensureRootExists()
    return store
}

func makeGeneratedFileStore(rootURL: URL) throws -> GeneratedFileStore {
    let store = GeneratedFileStore(
        rootURL: rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true),
        fileManager: .default
    )
    try store.ensureRootExists()
    return store
}

func makeGenerationJobStore(rootURL: URL) throws -> GenerationJobStore {
    let store = GenerationJobStore(
        rootURL: rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true),
        fileManager: .default
    )
    try store.ensureRootExists()
    return store
}

func makeRuntime<ResidentModelResult>(
    rootURL: URL = makeTempDirectoryURL(),
    output: OutputRecorder,
    playback: PlaybackSpy,
    speechBackend: SpeakSwiftly.SpeechBackend = .qwen3,
    audioLoadRecorder: ResidentModelRecorder? = nil,
    loadedAudioSamples: MLXArray? = nil,
    loadedCloneAudioSamples: [Float] = [],
    residentModelLoader: @escaping @Sendable (SpeakSwiftly.SpeechBackend) async throws -> ResidentModelResult,
    profileModelLoader: @escaping @Sendable () async throws -> AnySpeechModel = {
        makeProfileModel()
    },
    cloneTranscriptionModelLoader: @escaping @Sendable () async throws -> AnyCloneTranscriptionModel = {
        makeCloneTranscriptionModel()
    },
    readRuntimeMemory: @escaping @Sendable () -> RuntimeMemorySnapshot? = { nil }
) async throws -> WorkerRuntime {
    let store = try makeProfileStore(rootURL: rootURL)
    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    let generationJobStore = try makeGenerationJobStore(rootURL: rootURL)
    let normalizer = try SpeakSwiftly.Normalizer(
        persistenceURL: rootURL.appending(path: ProfileStore.textProfilesFileName)
    )
    let playbackController = playback.controller()
    let dependencies = WorkerDependencies(
        fileManager: .default,
        loadResidentModels: { backend in
            let loaded = try await residentModelLoader(backend)
            if let models = loaded as? ResidentSpeechModels {
                return models
            }
            if let model = loaded as? AnySpeechModel {
                switch backend {
                case .qwen3, .qwen3CustomVoice:
                    return .qwen3(model)
                case .marvis:
                    return .marvis(
                        MarvisResidentModels(
                            conversationalA: model,
                            conversationalB: model
                        )
                    )
                }
            }
            fatalError("Test support received an unexpected resident model loader result type: \(type(of: loaded))")
        },
        loadProfileModel: profileModelLoader,
        loadCloneTranscriptionModel: cloneTranscriptionModelLoader,
        makePlaybackController: { playbackController },
        writeWAV: { samples, _, url in
            let bytes = samples.map(\.bitPattern).flatMap { value in
                withUnsafeBytes(of: value.littleEndian, Array.init)
            }
            try Data(bytes).write(to: url, options: .atomic)
        },
        loadAudioSamples: { _, _ in
            audioLoadRecorder?.recordAudioLoad()
            return loadedAudioSamples
        },
        loadAudioFloats: { _, _ in
            loadedCloneAudioSamples
        },
        writeStdout: output.writeStdout,
        writeStderr: output.writeStderr,
        now: Date.init,
        readRuntimeMemory: readRuntimeMemory
    )

    let runtime = WorkerRuntime(
        dependencies: dependencies,
        speechBackend: speechBackend,
        profileStore: store,
        generatedFileStore: generatedFileStore,
        generationJobStore: generationJobStore,
        normalizer: normalizer,
        playbackController: PlaybackController(driver: playbackController)
    )
    await runtime.installPlaybackHooks()
    return runtime
}

extension ProfileStore {
    func createProfile(
        profileName: String,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        sampleRate: Int,
        canonicalAudioData: Data
    ) throws -> StoredProfile {
        try createProfile(
            profileName: profileName,
            vibe: inferredTestVibe(profileName: profileName, voiceDescription: voiceDescription),
            modelRepo: modelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            sampleRate: sampleRate,
            canonicalAudioData: canonicalAudioData
        )
    }
}

private func inferredTestVibe(profileName: String, voiceDescription: String) -> SpeakSwiftly.Vibe {
    let signal = "\(profileName) \(voiceDescription)".lowercased()
    if signal.contains("femme") || signal.contains("female") || signal.contains("feminine") {
        return .femme
    }
    if signal.contains("masc") || signal.contains("male") || signal.contains("masculine") {
        return .masc
    }
    return .androgenous
}

extension SpeakSwiftly.Voices {
    func create(
        design named: SpeakSwiftly.Name,
        from text: String,
        voice voiceDescription: String,
        outputPath: String? = nil
    ) async -> SpeakSwiftly.RequestHandle {
        await create(
            design: named,
            from: text,
            vibe: inferredTestVibe(profileName: named, voiceDescription: voiceDescription),
            voice: voiceDescription,
            outputPath: outputPath
        )
    }

    func create(
        clone named: SpeakSwiftly.Name,
        from referenceAudioURL: URL,
        transcript: String? = nil
    ) async -> SpeakSwiftly.RequestHandle {
        await create(
            clone: named,
            from: referenceAudioURL,
            vibe: inferredTestVibe(profileName: named, voiceDescription: transcript ?? ""),
            transcript: transcript
        )
    }
}

func makeTempDirectoryURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - Polling Helpers

func waitUntil(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if condition() {
            return true
        }

        try? await Task.sleep(for: pollInterval)
    }

    return condition()
}

private extension Array where Element == Float {
    static func asyncEnumerated(
        _ stream: AsyncThrowingStream<[Float], Error>
    ) -> AsyncThrowingStream<(Int, [Float]), Error> {
        AsyncThrowingStream { continuation in
            Task {
                var index = 0
                do {
                    for try await chunk in stream {
                        continuation.yield((index, chunk))
                        index += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
