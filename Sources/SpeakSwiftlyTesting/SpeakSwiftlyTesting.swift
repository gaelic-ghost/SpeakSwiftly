import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS
import SpeakSwiftly

@main
struct SpeakSwiftlyTestingMain {
    enum Command: String {
        case resources
        case status
        case smoke
        case createDesignProfile = "create-design-profile"
        case volumeProbe = "volume-probe"
        case compareVolume = "compare-volume"
        case matrixVolume = "matrix-volume"
        case captureQwenCodes = "capture-qwen-codes"
        case replayQwenCodes = "replay-qwen-codes"
        case compareQwenCodes = "compare-qwen-codes"
    }

    enum ConditioningMode: String {
        case auto
        case raw
        case artifact

        var runtimeStrategy: SpeakSwiftly.QwenConditioningStrategy {
            switch self {
                case .auto, .artifact:
                    .preparedConditioning
                case .raw:
                    .legacyRaw
            }
        }
    }

    struct CreateDesignProfileOptions {
        var profileName: String
        var sourceText = "Hello there from SpeakSwiftly end-to-end coverage."
        var vibe = "femme"
        var voiceDescription: String
        var profileRoot: String?
    }

    struct VolumeProbeOptions {
        var profileName = "default-femme"
        var profileRoot: String?
        var textFile: String?
        var repeatCount = 10
        var windowSeconds = 2.0
        var conditioningMode: ConditioningMode = .auto
    }

    struct MatrixVolumeOptions {
        var profileNames = [String]()
        var profileRoot: String?
        var shortTextFile: String?
        var longTextFile: String?
        var shortRepeatCount = 4
        var longRepeatCount = 14
        var iterations = 1
        var windowSeconds = 2.0
        var includeStreamed = false
    }

    struct CaptureQwenCodesOptions {
        enum Lane: String {
            case direct
        }

        var profileName = "default-femme"
        var profileRoot: String?
        var textFile: String?
        var repeatCount = 10
        var windowSeconds = 2.0
        var conditioningMode: ConditioningMode = .auto
        var lane: Lane = .direct
    }

    struct ReplayQwenCodesOptions {
        var artifactFile: String?
        var windowSeconds: Double?
    }

    struct CompareQwenCodesOptions {
        var leftArtifactFile: String?
        var rightArtifactFile: String?
    }

    struct VolumeWindow {
        let index: Int
        let startSeconds: Double
        let durationSeconds: Double
        let rms: Double
        let peak: Double
    }

    struct VolumeSegment {
        let label: String
        let rms: Double
        let peak: Double
    }

    struct VolumeSummary {
        let firstRMS: Double
        let lastRMS: Double
        let rmsDropPercent: Double
        let slopePerWindow: Double
        let firstPeak: Double
        let lastPeak: Double
        let headRMS: Double
        let tailRMS: Double
        let tailHeadRatio: Double
        let segments: [VolumeSegment]
    }

    struct ProbeAnalysis {
        let sampleRate: Int
        let windows: [VolumeWindow]
        let summary: VolumeSummary?
    }

    struct CompareRun {
        let lane: String
        let conditioningMode: ConditioningMode
        let generatedFilePath: String
        let analysis: ProbeAnalysis
    }

    struct QwenDebugCapture {
        let generatedCodes: EncodableInt32Tensor
        let referenceCodes: EncodableInt32Tensor?
        let referenceTextTokenIDs: EncodableInt32Tensor?
        let resolvedLanguage: String?
        let codecLanguageID: Int?
    }

    struct DirectQwenCaptureRun {
        let run: CompareRun
        let modelRepo: String
        let referenceAudioFile: String
        let referenceText: String
        let capture: QwenDebugCapture
    }

    struct ComparisonResult {
        let streamed: CompareRun
        let direct: CompareRun
    }

    struct ProbeProfileManifest: Decodable {
        let backendMaterializations: [ProbeMaterializationManifest]
        let qwenConditioningArtifacts: [ProbeConditioningArtifactManifest]
    }

    struct EncodableVolumeWindow: Encodable {
        let index: Int
        let startSeconds: Double
        let durationSeconds: Double
        let rms: Double
        let peak: Double
    }

    struct EncodableVolumeSegment: Encodable {
        let label: String
        let rms: Double
        let peak: Double
    }

    struct EncodableVolumeSummary: Encodable {
        let firstRMS: Double
        let lastRMS: Double
        let rmsDropPercent: Double
        let slopePerWindow: Double
        let firstPeak: Double
        let lastPeak: Double
        let headRMS: Double
        let tailRMS: Double
        let tailHeadRatio: Double
        let segments: [EncodableVolumeSegment]
    }

    struct EncodableProbeAnalysis: Encodable {
        let sampleRate: Int
        let windows: [EncodableVolumeWindow]
        let summary: EncodableVolumeSummary?
    }

    struct CompareRunArtifact: Encodable {
        let lane: String
        let conditioningMode: String
        let generatedFilePath: String
        let analysis: EncodableProbeAnalysis
    }

    struct ComparisonArtifact: Encodable {
        let profileName: String
        let profileRoot: String?
        let textCharacters: Int
        let textWords: Int
        let windowSeconds: Double
        let generatedAt: Date
        let streamed: CompareRunArtifact
        let direct: CompareRunArtifact
    }

    struct MatrixProbeRow: Encodable {
        let profileName: String
        let iteration: Int
        let textLabel: String
        let lane: String
        let conditioningMode: String
        let generatedFilePath: String
        let analysis: EncodableProbeAnalysis
    }

    struct MatrixProbeArtifact: Encodable {
        let generatedAt: Date
        let profileRoot: String?
        let iterations: Int
        let windowSeconds: Double
        let includeStreamed: Bool
        let rows: [MatrixProbeRow]
    }

    struct EncodableInt32Tensor: Encodable {
        let values: [Int32]
        let shape: [Int]
    }

    struct QwenCodeCaptureArtifact: Encodable {
        let schemaVersion: Int
        let generatedAt: Date
        let profileName: String
        let profileRoot: String?
        let requestText: String
        let textCharacters: Int
        let textWords: Int
        let conditioningMode: String
        let lane: String
        let modelRepo: String
        let referenceAudioFile: String
        let referenceText: String
        let generatedFilePath: String
        let sampleRate: Int
        let retainedAnalysis: EncodableProbeAnalysis
        let generatedCodes: EncodableInt32Tensor
        let referenceCodes: EncodableInt32Tensor?
        let referenceTextTokenIDs: EncodableInt32Tensor?
        let resolvedLanguage: String?
        let codecLanguageID: Int?
    }

    struct ReplayQwenCodesArtifact: Encodable {
        let schemaVersion: Int
        let generatedAt: Date
        let sourceArtifactPath: String
        let sourceGeneratedAt: Date
        let profileName: String
        let profileRoot: String?
        let conditioningMode: String
        let lane: String
        let modelRepo: String
        let sampleRate: Int
        let windowSeconds: Double
        let sourceRetainedAnalysis: EncodableProbeAnalysis
        let replayRuns: [ReplayRunArtifact]
    }

    struct ReplayRunArtifact: Encodable {
        let lane: String
        let generatedFilePath: String
        let analysis: EncodableProbeAnalysis
    }

    struct QwenCodeQuarterStats: Encodable {
        let label: String
        let frameCount: Int
        let exactAdjacentRepeatRatio: Double
        let distinctTokensMeanPerCodebook: Double
        let distinctTokensMinPerCodebook: Int
        let distinctTokensMaxPerCodebook: Int
        let longestRunMeanPerCodebook: Double
        let longestRunMaxPerCodebook: Int
    }

    struct QwenCodeArtifactStats: Encodable {
        let frameCount: Int
        let codebookCount: Int
        let totalTokenCount: Int
        let distinctTokenCount: Int
        let exactAdjacentRepeatRatio: Double
        let distinctTokensMeanPerCodebook: Double
        let distinctTokensMinPerCodebook: Int
        let distinctTokensMaxPerCodebook: Int
        let longestRunMeanPerCodebook: Double
        let longestRunMaxPerCodebook: Int
        let headTailDistinctJaccardMean: Double
        let headTailDistinctJaccardMin: Double
        let headTailDistributionShiftMean: Double
        let headTailDistributionShiftMax: Double
        let quarters: [QwenCodeQuarterStats]
    }

    struct QwenCodeArtifactDescriptor: Encodable {
        let artifactPath: String
        let profileName: String
        let conditioningMode: String
        let lane: String
        let modelRepo: String
        let generatedAt: Date
        let tailHeadRatio: Double?
        let stats: QwenCodeArtifactStats
    }

    struct QwenCodePairComparison: Encodable {
        let exactPositionMatchRatio: Double
        let exactPositionMatchMinPerCodebook: Double
        let exactPositionMatchMaxPerCodebook: Double
        let fullSequenceDistinctJaccardMean: Double
        let fullSequenceDistinctJaccardMin: Double
        let fullSequenceDistributionShiftMean: Double
        let fullSequenceDistributionShiftMax: Double
    }

    struct QwenCodeComparisonArtifact: Encodable {
        let schemaVersion: Int
        let generatedAt: Date
        let left: QwenCodeArtifactDescriptor
        let right: QwenCodeArtifactDescriptor
        let pair: QwenCodePairComparison
    }

    struct ProbeMaterializationManifest: Decodable {
        let backend: String
        let modelRepo: String
        let referenceAudioFile: String
        let referenceText: String
        let sampleRate: Int
    }

    struct ProbeConditioningArtifactManifest: Decodable {
        let backend: String
        let artifactFile: String
    }

    struct ProbePersistedQwenConditioningArtifact: Decodable {
        let speakerEmbedding: ProbeFloatTensor?
        let referenceSpeechCodes: ProbeInt32Tensor
        let referenceTextTokenIDs: ProbeInt32Tensor
        let resolvedLanguage: String
        let codecLanguageID: Int?

        func makeConditioning() -> Qwen3TTSModel.Qwen3TTSReferenceConditioning {
            Qwen3TTSModel.Qwen3TTSReferenceConditioning(
                speakerEmbedding: speakerEmbedding?.makeArray(),
                referenceSpeechCodes: referenceSpeechCodes.makeArray(),
                referenceTextTokenIDs: referenceTextTokenIDs.makeArray(),
                resolvedLanguage: resolvedLanguage,
                codecLanguageID: codecLanguageID,
            )
        }
    }

    struct ProbeFloatTensor: Decodable {
        let values: [Float]
        let shape: [Int]

        func makeArray() -> MLXArray {
            MLXArray(values).reshaped(shape)
        }
    }

    struct DecodableVolumeWindow: Decodable {
        let index: Int
        let startSeconds: Double
        let durationSeconds: Double
        let rms: Double
        let peak: Double
    }

    struct DecodableVolumeSegment: Decodable {
        let label: String
        let rms: Double
        let peak: Double
    }

    struct DecodableVolumeSummary: Decodable {
        let firstRMS: Double
        let lastRMS: Double
        let rmsDropPercent: Double
        let slopePerWindow: Double
        let firstPeak: Double
        let lastPeak: Double
        let headRMS: Double
        let tailRMS: Double
        let tailHeadRatio: Double
        let segments: [DecodableVolumeSegment]
    }

    struct DecodableProbeAnalysis: Decodable {
        let sampleRate: Int
        let windows: [DecodableVolumeWindow]
        let summary: DecodableVolumeSummary?

        func makeProbeAnalysis() -> ProbeAnalysis {
            ProbeAnalysis(
                sampleRate: sampleRate,
                windows: windows.map {
                    VolumeWindow(
                        index: $0.index,
                        startSeconds: $0.startSeconds,
                        durationSeconds: $0.durationSeconds,
                        rms: $0.rms,
                        peak: $0.peak,
                    )
                },
                summary: summary.map {
                    VolumeSummary(
                        firstRMS: $0.firstRMS,
                        lastRMS: $0.lastRMS,
                        rmsDropPercent: $0.rmsDropPercent,
                        slopePerWindow: $0.slopePerWindow,
                        firstPeak: $0.firstPeak,
                        lastPeak: $0.lastPeak,
                        headRMS: $0.headRMS,
                        tailRMS: $0.tailRMS,
                        tailHeadRatio: $0.tailHeadRatio,
                        segments: $0.segments.map {
                            VolumeSegment(label: $0.label, rms: $0.rms, peak: $0.peak)
                        },
                    )
                },
            )
        }
    }

    struct DecodableQwenCodeCaptureArtifact: Decodable {
        let generatedAt: Date
        let profileName: String
        let profileRoot: String?
        let conditioningMode: String
        let lane: String
        let modelRepo: String
        let sampleRate: Int
        let retainedAnalysis: DecodableProbeAnalysis
        let generatedCodes: ProbeInt32Tensor
        let referenceCodes: ProbeInt32Tensor?
        let referenceTextTokenIDs: ProbeInt32Tensor?
        let resolvedLanguage: String?
        let codecLanguageID: Int?
    }

    struct ProbeInt32Tensor: Decodable {
        let values: [Int32]
        let shape: [Int]

        func makeArray() -> MLXArray {
            MLXArray(values).reshaped(shape)
        }
    }

    static let profileRootOverrideEnvironmentVariable = "SPEAKSWIFTLY_PROFILE_ROOT"
    static let defaultProbeParagraph = """
    This is a long-form loudness probe for SpeakSwiftly. Please keep the voice steady, natural, and evenly projected from beginning to end. We are intentionally using a much longer passage so we can inspect whether the waveform stays consistent over time or gradually loses energy. The content itself is not important. What matters is that the generated speech remains stable, full, and equally audible throughout the entire passage, even after many seconds of continuous synthesis.
    """

    static func main() async {
        do {
            try await run()
        } catch {
            fputs("SpeakSwiftlyTesting failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = try parseCommand(arguments: arguments)

        switch command {
            case .resources:
                try printResources()
            case .status:
                try await printStatus()
            case .smoke:
                try printResources()
                try await printStatus()
            case .createDesignProfile:
                let options = try parseCreateDesignProfileOptions(arguments: arguments)
                try await runCreateDesignProfile(options: options)
            case .volumeProbe:
                let options = try parseVolumeProbeOptions(arguments: arguments)
                try await runVolumeProbe(options: options)
            case .compareVolume:
                let options = try parseVolumeProbeOptions(arguments: arguments)
                try await runCompareVolume(options: options)
            case .matrixVolume:
                let options = try parseMatrixVolumeOptions(arguments: arguments)
                try await runMatrixVolume(options: options)
            case .captureQwenCodes:
                let options = try parseCaptureQwenCodesOptions(arguments: arguments)
                try await runCaptureQwenCodes(options: options)
            case .replayQwenCodes:
                let options = try parseReplayQwenCodesOptions(arguments: arguments)
                try await runReplayQwenCodes(options: options)
            case .compareQwenCodes:
                let options = try parseCompareQwenCodesOptions(arguments: arguments)
                try runCompareQwenCodes(options: options)
        }
    }

    static func parseCommand(arguments: [String]) throws -> Command {
        guard let rawCommand = arguments.first else {
            throw UsageError.missingCommand
        }
        guard let command = Command(rawValue: rawCommand) else {
            throw UsageError.unknownCommand(rawCommand)
        }

        if command != .volumeProbe,
           command != .compareVolume,
           command != .matrixVolume,
           command != .captureQwenCodes,
           command != .replayQwenCodes,
           command != .compareQwenCodes,
           command != .createDesignProfile,
           arguments.count != 1 {
            throw UsageError.unexpectedArguments(arguments.dropFirst().joined(separator: " "))
        }

        return command
    }

    static func parseCreateDesignProfileOptions(arguments: [String]) throws -> CreateDesignProfileOptions {
        var profileName: String?
        var voiceDescription: String?
        var options = CreateDesignProfileOptions(
            profileName: "",
            voiceDescription: "",
        )
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--profile":
                    index += 1
                    profileName = try requireOptionValue(arguments, index: index, for: argument)
                case "--voice":
                    index += 1
                    voiceDescription = try requireOptionValue(arguments, index: index, for: argument)
                case "--text":
                    index += 1
                    options.sourceText = try requireOptionValue(arguments, index: index, for: argument)
                case "--vibe":
                    index += 1
                    options.vibe = try requireOptionValue(arguments, index: index, for: argument)
                case "--profile-root":
                    index += 1
                    options.profileRoot = try requireOptionValue(arguments, index: index, for: argument)
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        guard let profileName, !profileName.isEmpty else {
            throw UsageError.missingRequiredOption("--profile")
        }
        guard let voiceDescription, !voiceDescription.isEmpty else {
            throw UsageError.missingRequiredOption("--voice")
        }

        options.profileName = profileName
        options.voiceDescription = voiceDescription
        return options
    }

    static func parseVolumeProbeOptions(arguments: [String]) throws -> VolumeProbeOptions {
        var options = VolumeProbeOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--profile":
                    index += 1
                    options.profileName = try requireOptionValue(arguments, index: index, for: argument)
                case "--profile-root":
                    index += 1
                    options.profileRoot = try requireOptionValue(arguments, index: index, for: argument)
                case "--text-file":
                    index += 1
                    options.textFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--repeat":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let repeatCount = Int(value), repeatCount > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.repeatCount = repeatCount
                case "--window-seconds":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let windowSeconds = Double(value), windowSeconds > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.windowSeconds = windowSeconds
                case "--conditioning":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let conditioningMode = ConditioningMode(rawValue: value) else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.conditioningMode = conditioningMode
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        return options
    }

    static func parseMatrixVolumeOptions(arguments: [String]) throws -> MatrixVolumeOptions {
        var options = MatrixVolumeOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--profile":
                    index += 1
                    try options.profileNames.append(requireOptionValue(arguments, index: index, for: argument))
                case "--profile-root":
                    index += 1
                    options.profileRoot = try requireOptionValue(arguments, index: index, for: argument)
                case "--short-text-file":
                    index += 1
                    options.shortTextFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--long-text-file":
                    index += 1
                    options.longTextFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--short-repeat":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let repeatCount = Int(value), repeatCount > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.shortRepeatCount = repeatCount
                case "--long-repeat":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let repeatCount = Int(value), repeatCount > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.longRepeatCount = repeatCount
                case "--iterations":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let iterations = Int(value), iterations > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.iterations = iterations
                case "--window-seconds":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let windowSeconds = Double(value), windowSeconds > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.windowSeconds = windowSeconds
                case "--include-streamed":
                    options.includeStreamed = true
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        if options.profileNames.isEmpty {
            options.profileNames = ["default-femme"]
        }

        return options
    }

    static func parseCaptureQwenCodesOptions(arguments: [String]) throws -> CaptureQwenCodesOptions {
        var options = CaptureQwenCodesOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--profile":
                    index += 1
                    options.profileName = try requireOptionValue(arguments, index: index, for: argument)
                case "--profile-root":
                    index += 1
                    options.profileRoot = try requireOptionValue(arguments, index: index, for: argument)
                case "--text-file":
                    index += 1
                    options.textFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--repeat":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let repeatCount = Int(value), repeatCount > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.repeatCount = repeatCount
                case "--window-seconds":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let windowSeconds = Double(value), windowSeconds > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.windowSeconds = windowSeconds
                case "--conditioning":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let conditioningMode = ConditioningMode(rawValue: value) else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.conditioningMode = conditioningMode
                case "--lane":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let lane = CaptureQwenCodesOptions.Lane(rawValue: value) else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.lane = lane
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        return options
    }

    static func parseReplayQwenCodesOptions(arguments: [String]) throws -> ReplayQwenCodesOptions {
        var options = ReplayQwenCodesOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--artifact-file":
                    index += 1
                    options.artifactFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--window-seconds":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let windowSeconds = Double(value), windowSeconds > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.windowSeconds = windowSeconds
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        return options
    }

    static func parseCompareQwenCodesOptions(arguments: [String]) throws -> CompareQwenCodesOptions {
        var options = CompareQwenCodesOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--left-artifact-file":
                    index += 1
                    options.leftArtifactFile = try requireOptionValue(arguments, index: index, for: argument)
                case "--right-artifact-file":
                    index += 1
                    options.rightArtifactFile = try requireOptionValue(arguments, index: index, for: argument)
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        return options
    }

    static func requireOptionValue(
        _ arguments: [String],
        index: Int,
        for option: String,
    ) throws -> String {
        guard index < arguments.count else {
            throw UsageError.missingOptionValue(option)
        }

        return arguments[index]
    }

    static func printResources() throws {
        let packageBundleURL = SpeakSwiftly.SupportResources.bundle.bundleURL
        let mlxBundleURL = try SpeakSwiftly.SupportResources.mlxBundleURL()
        let defaultMetallibURL = try SpeakSwiftly.SupportResources.defaultMetallibURL()

        print("package_bundle: \(packageBundleURL.path)")
        print("mlx_bundle: \(mlxBundleURL.path)")
        print("default_metallib: \(defaultMetallibURL.path)")
    }

    static func printStatus() async throws {
        let runtime = await SpeakSwiftly.liftoff()
        await runtime.start()

        let handle = await runtime.status()
        print("request_id: \(handle.id)")
        print("operation: \(handle.operation)")

        for try await event in handle.events {
            switch event {
                case let .queued(queued):
                    print("queued: position=\(queued.queuePosition) reason=\(queued.reason.rawValue)")
                case let .acknowledged(success):
                    print("acknowledged: \(formatStatus(success.status))")
                    return
                case let .started(started):
                    print("started: op=\(started.op)")
                case let .progress(progress):
                    print("progress: stage=\(progress.stage.rawValue)")
                case let .completed(success):
                    print("completed: \(formatStatus(success.status))")
                    return
            }
        }

        throw UsageError.statusStreamEndedWithoutTerminalEvent
    }

    static func runVolumeProbe(options: VolumeProbeOptions) async throws {
        if let profileRoot = options.profileRoot {
            setenv(profileRootOverrideEnvironmentVariable, profileRoot, 1)
        }

        try validateConditioningMode(
            profileName: options.profileName,
            profileRootOverride: options.profileRoot,
            conditioningMode: options.conditioningMode,
        )

        let text = try loadVolumeProbeText(options: options)
        let result = try await runStreamedProbe(
            profileName: options.profileName,
            text: text,
            windowSeconds: options.windowSeconds,
            conditioningMode: options.conditioningMode,
        )

        print("profile_name: \(options.profileName)")
        if let profileRoot = options.profileRoot {
            print("profile_root: \(profileRoot)")
        }
        print("conditioning_mode: \(options.conditioningMode.rawValue)")
        print("text_characters: \(text.count)")
        print("text_words: \(text.split(whereSeparator: \.isWhitespace).count)")
        print("generated_file: \(result.generatedFilePath)")
        print("sample_rate: \(result.analysis.sampleRate)")
        print("window_seconds: \(options.windowSeconds)")

        printAnalysis(result.analysis, prefix: "window", summaryLabel: "summary")
    }

    static func runCreateDesignProfile(options: CreateDesignProfileOptions) async throws {
        if let profileRoot = options.profileRoot {
            setenv(profileRootOverrideEnvironmentVariable, profileRoot, 1)
        }

        let vibe = try parseVibe(options.vibe)
        let runtime = await SpeakSwiftly.liftoff()
        await runtime.start()
        let handle = await runtime.voices.create(
            design: options.profileName,
            from: options.sourceText,
            vibe: vibe,
            voice: options.voiceDescription,
        )
        let created = try await awaitCreatedProfile(from: handle)

        print("profile_name: \(created.profileName)")
        print("profile_path: \(created.profilePath)")
        print("source_text: \(options.sourceText)")
        print("voice_description: \(options.voiceDescription)")
        print("vibe: \(vibe.rawValue)")
        if let profileRoot = options.profileRoot {
            print("profile_root: \(profileRoot)")
        }
    }

    static func runCompareVolume(options: VolumeProbeOptions) async throws {
        if let profileRoot = options.profileRoot {
            setenv(profileRootOverrideEnvironmentVariable, profileRoot, 1)
        }

        let text = try loadVolumeProbeText(options: options)
        let comparison = try await compareVolume(options: options, text: text)

        print("profile_name: \(options.profileName)")
        if let profileRoot = options.profileRoot {
            print("profile_root: \(profileRoot)")
        }
        print("conditioning_mode: \(options.conditioningMode.rawValue)")
        print("text_characters: \(text.count)")
        print("text_words: \(text.split(whereSeparator: \.isWhitespace).count)")
        print("window_seconds: \(options.windowSeconds)")
        print("streamed_generated_file: \(comparison.streamed.generatedFilePath)")
        print("streamed_sample_rate: \(comparison.streamed.analysis.sampleRate)")
        print("direct_generated_file: \(comparison.direct.generatedFilePath)")
        print("direct_sample_rate: \(comparison.direct.analysis.sampleRate)")

        printAnalysis(
            comparison.streamed.analysis,
            prefix: "streamed_window",
            summaryLabel: "streamed_summary",
        )
        printAnalysis(
            comparison.direct.analysis,
            prefix: "direct_window",
            summaryLabel: "direct_summary",
        )

        if let streamedSummary = comparison.streamed.analysis.summary,
           let directSummary = comparison.direct.analysis.summary {
            print(
                String(
                    format: "comparison: streamed_last_rms=%.5f direct_last_rms=%.5f streamed_drop_pct=%.2f direct_drop_pct=%.2f drop_delta_pct=%.2f streamed_slope=%.6f direct_slope=%.6f",
                    streamedSummary.lastRMS,
                    directSummary.lastRMS,
                    streamedSummary.rmsDropPercent,
                    directSummary.rmsDropPercent,
                    streamedSummary.rmsDropPercent - directSummary.rmsDropPercent,
                    streamedSummary.slopePerWindow,
                    directSummary.slopePerWindow,
                ),
            )
        }

        let artifactURL = try writeProbeArtifact(
            ComparisonArtifact(
                profileName: options.profileName,
                profileRoot: options.profileRoot,
                textCharacters: text.count,
                textWords: text.split(whereSeparator: \.isWhitespace).count,
                windowSeconds: options.windowSeconds,
                generatedAt: Date(),
                streamed: makeCompareRunArtifact(comparison.streamed),
                direct: makeCompareRunArtifact(comparison.direct),
            ),
            stem: "compare-volume",
            latestFilename: "compare-volume-latest.json",
        )
        print("json_artifact: \(artifactURL.path)")
    }

    static func runCaptureQwenCodes(options: CaptureQwenCodesOptions) async throws {
        if let profileRoot = options.profileRoot {
            setenv(profileRootOverrideEnvironmentVariable, profileRoot, 1)
        }

        try validateConditioningMode(
            profileName: options.profileName,
            profileRootOverride: options.profileRoot,
            conditioningMode: options.conditioningMode,
        )

        let text = try loadVolumeProbeText(
            options: VolumeProbeOptions(
                profileName: options.profileName,
                profileRoot: options.profileRoot,
                textFile: options.textFile,
                repeatCount: options.repeatCount,
                windowSeconds: options.windowSeconds,
                conditioningMode: options.conditioningMode,
            ),
        )
        let (profileDirectoryURL, manifest) = try probeProfileContext(
            profileName: options.profileName,
            profileRootOverride: options.profileRoot,
        )

        let captureRun = switch options.lane {
            case .direct:
                try await runDirectQwenCapture(
                    text: text,
                    manifest: manifest,
                    profileDirectoryURL: profileDirectoryURL,
                    windowSeconds: options.windowSeconds,
                    conditioningMode: options.conditioningMode,
                    outputStem: "\(options.profileName)-\(options.conditioningMode.rawValue)-capture-direct",
                )
        }

        print("profile_name: \(options.profileName)")
        if let profileRoot = options.profileRoot {
            print("profile_root: \(profileRoot)")
        }
        print("conditioning_mode: \(options.conditioningMode.rawValue)")
        print("lane: \(options.lane.rawValue)")
        print("text_characters: \(text.count)")
        print("text_words: \(text.split(whereSeparator: \.isWhitespace).count)")
        print("model_repo: \(captureRun.modelRepo)")
        print("reference_audio_file: \(captureRun.referenceAudioFile)")
        print("generated_file: \(captureRun.run.generatedFilePath)")
        print("sample_rate: \(captureRun.run.analysis.sampleRate)")
        print("window_seconds: \(options.windowSeconds)")
        print("generated_code_shape: \(captureRun.capture.generatedCodes.shape)")
        print("generated_code_values: \(captureRun.capture.generatedCodes.values.count)")
        if let referenceCodes = captureRun.capture.referenceCodes {
            print("reference_code_shape: \(referenceCodes.shape)")
            print("reference_code_values: \(referenceCodes.values.count)")
        }
        if let referenceTextTokenIDs = captureRun.capture.referenceTextTokenIDs {
            print("reference_text_token_ids_shape: \(referenceTextTokenIDs.shape)")
            print("reference_text_token_ids_values: \(referenceTextTokenIDs.values.count)")
        }
        if let resolvedLanguage = captureRun.capture.resolvedLanguage {
            print("resolved_language: \(resolvedLanguage)")
        }
        if let codecLanguageID = captureRun.capture.codecLanguageID {
            print("codec_language_id: \(codecLanguageID)")
        }

        printAnalysis(captureRun.run.analysis, prefix: "window", summaryLabel: "summary")

        let artifactURL = try writeProbeArtifact(
            QwenCodeCaptureArtifact(
                schemaVersion: 1,
                generatedAt: Date(),
                profileName: options.profileName,
                profileRoot: options.profileRoot,
                requestText: text,
                textCharacters: text.count,
                textWords: text.split(whereSeparator: \.isWhitespace).count,
                conditioningMode: options.conditioningMode.rawValue,
                lane: options.lane.rawValue,
                modelRepo: captureRun.modelRepo,
                referenceAudioFile: captureRun.referenceAudioFile,
                referenceText: captureRun.referenceText,
                generatedFilePath: captureRun.run.generatedFilePath,
                sampleRate: captureRun.run.analysis.sampleRate,
                retainedAnalysis: makeEncodableProbeAnalysis(captureRun.run.analysis),
                generatedCodes: captureRun.capture.generatedCodes,
                referenceCodes: captureRun.capture.referenceCodes,
                referenceTextTokenIDs: captureRun.capture.referenceTextTokenIDs,
                resolvedLanguage: captureRun.capture.resolvedLanguage,
                codecLanguageID: captureRun.capture.codecLanguageID,
            ),
            stem: "capture-qwen-codes",
            latestFilename: "capture-qwen-codes-latest.json",
        )
        print("json_artifact: \(artifactURL.path)")
    }

    static func runReplayQwenCodes(options: ReplayQwenCodesOptions) async throws {
        let artifactURL = try replayArtifactURL(options: options)
        let sourceArtifact = try loadCapturedQwenCodeArtifact(from: artifactURL)
        let retainedAnalysis = sourceArtifact.retainedAnalysis.makeProbeAnalysis()
        let windowSeconds = options.windowSeconds
            ?? retainedAnalysis.windows.first?.durationSeconds
            ?? 2.0

        let loadedModel = try await TTS.loadModel(modelRepo: sourceArtifact.modelRepo)
        guard let qwenModel = loadedModel as? Qwen3TTSModel else {
            throw UsageError.profileModelIsNotQwen(sourceArtifact.modelRepo)
        }

        let generatedCodes = sourceArtifact.generatedCodes.makeArray()
        let referenceCodes = sourceArtifact.referenceCodes?.makeArray()
        let decodeCodes = makeReplayDecodeCodes(
            generatedCodes: generatedCodes,
            referenceCodes: referenceCodes,
        )

        let boundedSamples = trimDecodedReferencePrefix(
            qwenModel.debugBoundedDecode(decodeCodes).asArray(Float.self),
            generatedCodes: generatedCodes,
            referenceCodes: referenceCodes,
        )
        let helperSamples = trimDecodedReferencePrefix(
            qwenModel.debugDecodeChunk(decodeCodes).asArray(Float.self),
            generatedCodes: generatedCodes,
            referenceCodes: referenceCodes,
        )
        let streamingSamples = qwenModel.debugStreamingDecode(
            generatedCodes: generatedCodes,
            referenceCodes: referenceCodes,
            chunkTokens: 300,
            warmWithReferenceCodes: false,
        )
        .asArray(Float.self)
        let warmedStreamingSamples = qwenModel.debugStreamingDecode(
            generatedCodes: generatedCodes,
            referenceCodes: referenceCodes,
            chunkTokens: 300,
            warmWithReferenceCodes: true,
        )
        .asArray(Float.self)

        let boundedRun = try makeReplayRun(
            lane: "bounded_decode",
            samples: boundedSamples,
            sampleRate: sourceArtifact.sampleRate,
            windowSeconds: windowSeconds,
            outputStem: "\(sourceArtifact.profileName)-replay-bounded",
        )
        let helperRun = try makeReplayRun(
            lane: "helper_decode_chunk",
            samples: helperSamples,
            sampleRate: sourceArtifact.sampleRate,
            windowSeconds: windowSeconds,
            outputStem: "\(sourceArtifact.profileName)-replay-helper",
        )
        let streamingRun = try makeReplayRun(
            lane: "streaming_decode",
            samples: streamingSamples,
            sampleRate: sourceArtifact.sampleRate,
            windowSeconds: windowSeconds,
            outputStem: "\(sourceArtifact.profileName)-replay-streaming",
        )
        let warmedRun = try makeReplayRun(
            lane: "warmed_streaming_decode",
            samples: warmedStreamingSamples,
            sampleRate: sourceArtifact.sampleRate,
            windowSeconds: windowSeconds,
            outputStem: "\(sourceArtifact.profileName)-replay-warmed-streaming",
        )

        print("source_artifact: \(artifactURL.path)")
        print("source_generated_at: \(ISO8601DateFormatter().string(from: sourceArtifact.generatedAt))")
        print("profile_name: \(sourceArtifact.profileName)")
        if let profileRoot = sourceArtifact.profileRoot {
            print("profile_root: \(profileRoot)")
        }
        print("conditioning_mode: \(sourceArtifact.conditioningMode)")
        print("lane: \(sourceArtifact.lane)")
        print("model_repo: \(sourceArtifact.modelRepo)")
        print("sample_rate: \(sourceArtifact.sampleRate)")
        print("window_seconds: \(windowSeconds)")
        print("generated_code_shape: \(sourceArtifact.generatedCodes.shape)")
        print("generated_code_values: \(sourceArtifact.generatedCodes.values.count)")
        if let referenceCodes = sourceArtifact.referenceCodes {
            print("reference_code_shape: \(referenceCodes.shape)")
            print("reference_code_values: \(referenceCodes.values.count)")
        }
        if let referenceTextTokenIDs = sourceArtifact.referenceTextTokenIDs {
            print("reference_text_token_ids_shape: \(referenceTextTokenIDs.shape)")
            print("reference_text_token_ids_values: \(referenceTextTokenIDs.values.count)")
        }
        if let resolvedLanguage = sourceArtifact.resolvedLanguage {
            print("resolved_language: \(resolvedLanguage)")
        }
        if let codecLanguageID = sourceArtifact.codecLanguageID {
            print("codec_language_id: \(codecLanguageID)")
        }

        if let retainedSummary = retainedAnalysis.summary {
            print(
                String(
                    format: "source_retained_summary: first_rms=%.5f last_rms=%.5f rms_drop_pct=%.2f head_rms=%.5f tail_rms=%.5f tail_head_ratio=%.5f",
                    retainedSummary.firstRMS,
                    retainedSummary.lastRMS,
                    retainedSummary.rmsDropPercent,
                    retainedSummary.headRMS,
                    retainedSummary.tailRMS,
                    retainedSummary.tailHeadRatio,
                ),
            )
        }

        for run in [boundedRun, helperRun, streamingRun, warmedRun] {
            print("replay_lane: \(run.lane)")
            print("generated_file: \(run.generatedFilePath)")
            printAnalysis(run.analysis, prefix: run.lane, summaryLabel: "\(run.lane)_summary")
        }

        let replayArtifactURL = try writeProbeArtifact(
            ReplayQwenCodesArtifact(
                schemaVersion: 1,
                generatedAt: Date(),
                sourceArtifactPath: artifactURL.path,
                sourceGeneratedAt: sourceArtifact.generatedAt,
                profileName: sourceArtifact.profileName,
                profileRoot: sourceArtifact.profileRoot,
                conditioningMode: sourceArtifact.conditioningMode,
                lane: sourceArtifact.lane,
                modelRepo: sourceArtifact.modelRepo,
                sampleRate: sourceArtifact.sampleRate,
                windowSeconds: windowSeconds,
                sourceRetainedAnalysis: makeEncodableProbeAnalysis(retainedAnalysis),
                replayRuns: [boundedRun, helperRun, streamingRun, warmedRun].map {
                    ReplayRunArtifact(
                        lane: $0.lane,
                        generatedFilePath: $0.generatedFilePath,
                        analysis: makeEncodableProbeAnalysis($0.analysis),
                    )
                },
            ),
            stem: "replay-qwen-codes",
            latestFilename: "replay-qwen-codes-latest.json",
        )
        print("json_artifact: \(replayArtifactURL.path)")
    }

    static func runCompareQwenCodes(options: CompareQwenCodesOptions) throws {
        let leftArtifactURL = try qwenComparisonArtifactURL(
            path: options.leftArtifactFile,
            option: "--left-artifact-file",
        )
        let rightArtifactURL = try qwenComparisonArtifactURL(
            path: options.rightArtifactFile,
            option: "--right-artifact-file",
        )
        let leftArtifact = try loadCapturedQwenCodeArtifact(from: leftArtifactURL)
        let rightArtifact = try loadCapturedQwenCodeArtifact(from: rightArtifactURL)

        let leftStats = try summarizeQwenCodes(leftArtifact.generatedCodes)
        let rightStats = try summarizeQwenCodes(rightArtifact.generatedCodes)
        let pair = try compareQwenCodeTensors(
            leftArtifact.generatedCodes,
            rightArtifact.generatedCodes,
        )

        let leftDescriptor = QwenCodeArtifactDescriptor(
            artifactPath: leftArtifactURL.path,
            profileName: leftArtifact.profileName,
            conditioningMode: leftArtifact.conditioningMode,
            lane: leftArtifact.lane,
            modelRepo: leftArtifact.modelRepo,
            generatedAt: leftArtifact.generatedAt,
            tailHeadRatio: leftArtifact.retainedAnalysis.summary?.tailHeadRatio,
            stats: leftStats,
        )
        let rightDescriptor = QwenCodeArtifactDescriptor(
            artifactPath: rightArtifactURL.path,
            profileName: rightArtifact.profileName,
            conditioningMode: rightArtifact.conditioningMode,
            lane: rightArtifact.lane,
            modelRepo: rightArtifact.modelRepo,
            generatedAt: rightArtifact.generatedAt,
            tailHeadRatio: rightArtifact.retainedAnalysis.summary?.tailHeadRatio,
            stats: rightStats,
        )

        print("left_artifact: \(leftArtifactURL.path)")
        print("left_profile: \(leftArtifact.profileName)")
        print("left_conditioning_mode: \(leftArtifact.conditioningMode)")
        if let tailHeadRatio = leftArtifact.retainedAnalysis.summary?.tailHeadRatio {
            print(String(format: "left_tail_head_ratio: %.5f", tailHeadRatio))
        }
        printQwenCodeArtifactStats(leftStats, prefix: "left")

        print("right_artifact: \(rightArtifactURL.path)")
        print("right_profile: \(rightArtifact.profileName)")
        print("right_conditioning_mode: \(rightArtifact.conditioningMode)")
        if let tailHeadRatio = rightArtifact.retainedAnalysis.summary?.tailHeadRatio {
            print(String(format: "right_tail_head_ratio: %.5f", tailHeadRatio))
        }
        printQwenCodeArtifactStats(rightStats, prefix: "right")

        print(
            String(
                format: "pair_summary: exact_match_ratio=%.5f exact_match_min_per_codebook=%.5f exact_match_max_per_codebook=%.5f distinct_jaccard_mean=%.5f distinct_jaccard_min=%.5f distribution_shift_mean=%.5f distribution_shift_max=%.5f",
                pair.exactPositionMatchRatio,
                pair.exactPositionMatchMinPerCodebook,
                pair.exactPositionMatchMaxPerCodebook,
                pair.fullSequenceDistinctJaccardMean,
                pair.fullSequenceDistinctJaccardMin,
                pair.fullSequenceDistributionShiftMean,
                pair.fullSequenceDistributionShiftMax,
            ),
        )

        let comparisonArtifactURL = try writeProbeArtifact(
            QwenCodeComparisonArtifact(
                schemaVersion: 1,
                generatedAt: Date(),
                left: leftDescriptor,
                right: rightDescriptor,
                pair: pair,
            ),
            stem: "compare-qwen-codes",
            latestFilename: "compare-qwen-codes-latest.json",
        )
        print("json_artifact: \(comparisonArtifactURL.path)")
    }

    static func loadVolumeProbeText(options: VolumeProbeOptions) throws -> String {
        if let textFile = options.textFile {
            let text = try String(contentsOfFile: textFile, encoding: .utf8)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw UsageError.emptyProbeText
            }

            return trimmed
        }

        return makeProbeText(repeatCount: options.repeatCount)
    }

    static func qwenComparisonArtifactURL(path: String?, option: String) throws -> URL {
        guard let path else {
            throw UsageError.missingRequiredOption(option)
        }

        return URL(fileURLWithPath: path, isDirectory: false)
    }

    static func runMatrixVolume(options: MatrixVolumeOptions) async throws {
        if let profileRoot = options.profileRoot {
            setenv(profileRootOverrideEnvironmentVariable, profileRoot, 1)
        }

        let shortText = try loadMatrixText(
            textFile: options.shortTextFile,
            repeatCount: options.shortRepeatCount,
        )
        let longText = try loadMatrixText(
            textFile: options.longTextFile,
            repeatCount: options.longRepeatCount,
        )
        var rows = [MatrixProbeRow]()

        for profileName in options.profileNames {
            let (profileDirectoryURL, manifest) = try probeProfileContext(
                profileName: profileName,
                profileRootOverride: options.profileRoot,
            )
            let hasStoredConditioning = manifest.qwenConditioningArtifacts.contains { $0.backend == "qwen3" }

            for iteration in 1...options.iterations {
                for (textLabel, text) in [("short", shortText), ("long", longText)] {
                    let rawDirect = try await runDirectProbe(
                        text: text,
                        manifest: manifest,
                        profileDirectoryURL: profileDirectoryURL,
                        windowSeconds: options.windowSeconds,
                        conditioningMode: .raw,
                        outputStem: "\(profileName)-\(textLabel)-raw-direct-\(iteration)",
                    )
                    rows.append(
                        MatrixProbeRow(
                            profileName: profileName,
                            iteration: iteration,
                            textLabel: textLabel,
                            lane: rawDirect.lane,
                            conditioningMode: rawDirect.conditioningMode.rawValue,
                            generatedFilePath: rawDirect.generatedFilePath,
                            analysis: makeEncodableProbeAnalysis(rawDirect.analysis),
                        ),
                    )

                    if hasStoredConditioning {
                        let artifactDirect = try await runDirectProbe(
                            text: text,
                            manifest: manifest,
                            profileDirectoryURL: profileDirectoryURL,
                            windowSeconds: options.windowSeconds,
                            conditioningMode: .artifact,
                            outputStem: "\(profileName)-\(textLabel)-artifact-direct-\(iteration)",
                        )
                        rows.append(
                            MatrixProbeRow(
                                profileName: profileName,
                                iteration: iteration,
                                textLabel: textLabel,
                                lane: artifactDirect.lane,
                                conditioningMode: artifactDirect.conditioningMode.rawValue,
                                generatedFilePath: artifactDirect.generatedFilePath,
                                analysis: makeEncodableProbeAnalysis(artifactDirect.analysis),
                            ),
                        )
                    }

                    if options.includeStreamed {
                        let rawStreamed = try await runStreamedProbe(
                            profileName: profileName,
                            text: text,
                            windowSeconds: options.windowSeconds,
                            conditioningMode: .raw,
                        )
                        rows.append(
                            MatrixProbeRow(
                                profileName: profileName,
                                iteration: iteration,
                                textLabel: textLabel,
                                lane: rawStreamed.lane,
                                conditioningMode: rawStreamed.conditioningMode.rawValue,
                                generatedFilePath: rawStreamed.generatedFilePath,
                                analysis: makeEncodableProbeAnalysis(rawStreamed.analysis),
                            ),
                        )

                        if hasStoredConditioning {
                            let artifactStreamed = try await runStreamedProbe(
                                profileName: profileName,
                                text: text,
                                windowSeconds: options.windowSeconds,
                                conditioningMode: .artifact,
                            )
                            rows.append(
                                MatrixProbeRow(
                                    profileName: profileName,
                                    iteration: iteration,
                                    textLabel: textLabel,
                                    lane: artifactStreamed.lane,
                                    conditioningMode: artifactStreamed.conditioningMode.rawValue,
                                    generatedFilePath: artifactStreamed.generatedFilePath,
                                    analysis: makeEncodableProbeAnalysis(artifactStreamed.analysis),
                                ),
                            )
                        }
                    }
                }
            }
        }

        for row in rows {
            if let summary = row.analysis.summary {
                print(
                    String(
                        format: "matrix_row: profile=%@ iteration=%d text=%@ lane=%@ conditioning=%@ head_rms=%.5f tail_rms=%.5f tail_head_ratio=%.5f first_rms=%.5f last_rms=%.5f drop_pct=%.2f slope=%.6f file=%@",
                        row.profileName,
                        row.iteration,
                        row.textLabel,
                        row.lane,
                        row.conditioningMode,
                        summary.headRMS,
                        summary.tailRMS,
                        summary.tailHeadRatio,
                        summary.firstRMS,
                        summary.lastRMS,
                        summary.rmsDropPercent,
                        summary.slopePerWindow,
                        row.generatedFilePath,
                    ),
                )
            }
        }

        let artifactURL = try writeProbeArtifact(
            MatrixProbeArtifact(
                generatedAt: Date(),
                profileRoot: options.profileRoot,
                iterations: options.iterations,
                windowSeconds: options.windowSeconds,
                includeStreamed: options.includeStreamed,
                rows: rows,
            ),
            stem: "matrix-volume",
            latestFilename: "matrix-volume-latest.json",
        )
        print("json_artifact: \(artifactURL.path)")
    }

    static func awaitGeneratedFile(
        from handle: SpeakSwiftly.RequestHandle,
    ) async throws -> SpeakSwiftly.GeneratedFile {
        for try await event in handle.events {
            switch event {
                case .queued, .started, .progress:
                    continue
                case let .acknowledged(success), let .completed(success):
                    if let generatedFile = success.generatedFile {
                        return generatedFile
                    }
            }
        }

        throw UsageError.volumeProbeEndedWithoutGeneratedFile
    }

    static func awaitCreatedProfile(
        from handle: SpeakSwiftly.RequestHandle,
    ) async throws -> (profileName: String, profilePath: String) {
        for try await event in handle.events {
            switch event {
                case .queued, .started, .progress:
                    continue
                case let .acknowledged(success), let .completed(success):
                    if let profileName = success.profileName, let profilePath = success.profilePath {
                        return (profileName, profilePath)
                    }
            }
        }

        throw UsageError.createProfileEndedWithoutProfilePayload
    }

    static func parseVibe(_ rawValue: String) throws -> SpeakSwiftly.Vibe {
        guard let vibe = SpeakSwiftly.Vibe(rawValue: rawValue) else {
            throw UsageError.invalidOptionValue("--vibe", rawValue)
        }

        return vibe
    }

    static func runStreamedProbe(
        profileName: String,
        text: String,
        windowSeconds: Double,
        conditioningMode: ConditioningMode,
    ) async throws -> CompareRun {
        let runtime = await SpeakSwiftly.liftoff(
            configuration: SpeakSwiftly.Configuration(
                speechBackend: .qwen3,
                qwenConditioningStrategy: conditioningMode.runtimeStrategy,
            ),
        )
        await runtime.start()

        let handle = await runtime.generate.audio(
            text: text,
            with: profileName,
        )

        let generatedFile = try await awaitGeneratedFile(from: handle)
        let analysis = try analyzeVolume(
            at: generatedFile.filePath,
            sampleRate: generatedFile.sampleRate,
            windowSeconds: windowSeconds,
        )

        return CompareRun(
            lane: "streamed",
            conditioningMode: conditioningMode,
            generatedFilePath: generatedFile.filePath,
            analysis: analysis,
        )
    }

    static func compareVolume(
        options: VolumeProbeOptions,
        text: String,
    ) async throws -> ComparisonResult {
        let (profileDirectoryURL, manifest) = try probeProfileContext(
            profileName: options.profileName,
            profileRootOverride: options.profileRoot,
        )
        if options.conditioningMode == .artifact,
           try loadStoredConditioning(manifest: manifest, profileDirectoryURL: profileDirectoryURL) == nil {
            throw UsageError.profileMissingStoredConditioning(profileDirectoryURL.path)
        }

        let streamed = try await runStreamedProbe(
            profileName: options.profileName,
            text: text,
            windowSeconds: options.windowSeconds,
            conditioningMode: options.conditioningMode,
        )
        let direct = try await runDirectProbe(
            text: text,
            manifest: manifest,
            profileDirectoryURL: profileDirectoryURL,
            windowSeconds: options.windowSeconds,
            conditioningMode: options.conditioningMode,
            outputStem: "\(options.profileName)-\(options.conditioningMode.rawValue)-direct",
        )
        return ComparisonResult(streamed: streamed, direct: direct)
    }

    static func runDirectQwenCapture(
        text: String,
        manifest: ProbeProfileManifest,
        profileDirectoryURL: URL,
        windowSeconds: Double,
        conditioningMode: ConditioningMode,
        outputStem: String,
    ) async throws -> DirectQwenCaptureRun {
        guard let materialization = manifest.backendMaterializations.first(where: { $0.backend == "qwen3" }) else {
            throw UsageError.profileMissingQwenMaterialization(profileDirectoryURL.path)
        }

        let loadedModel = try await TTS.loadModel(modelRepo: materialization.modelRepo)
        guard let qwenModel = loadedModel as? Qwen3TTSModel else {
            throw UsageError.profileModelIsNotQwen(materialization.modelRepo)
        }

        var generationParameters = qwenModel.defaultGenerationParameters
        let wordCount = max(text.split(whereSeparator: \.isWhitespace).count, 1)
        generationParameters.maxTokens = min(2048, max(56, wordCount * 8))
        generationParameters.temperature = 0.9
        generationParameters.topP = 1.0
        generationParameters.repetitionPenalty = 1.05
        let conditioning = try makeDirectConditioning(
            qwenModel: qwenModel,
            manifest: manifest,
            materialization: materialization,
            profileDirectoryURL: profileDirectoryURL,
            conditioningMode: conditioningMode,
        )
        var debugCapture: Qwen3TTSModel.DebugGeneratedCodes?
        let directSamples = try await qwenModel.generate(
            text: text,
            conditioning: conditioning.conditioning,
            generationParameters: generationParameters,
            onGeneratedCodes: { debug in
                debugCapture = debug
            },
        )
        .asArray(Float.self)
        guard let debugCapture else {
            throw UsageError.qwenGeneratedCodesMissing(materialization.modelRepo)
        }

        let directOutputURL = try writeProbeWAV(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            name: "\(outputStem).wav",
        )
        let analysis = analyzeVolume(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            windowSeconds: windowSeconds,
        )

        return DirectQwenCaptureRun(
            run: CompareRun(
                lane: "direct",
                conditioningMode: conditioningMode,
                generatedFilePath: directOutputURL.path,
                analysis: analysis,
            ),
            modelRepo: materialization.modelRepo,
            referenceAudioFile: materialization.referenceAudioFile,
            referenceText: materialization.referenceText,
            capture: QwenDebugCapture(
                generatedCodes: encodeInt32Tensor(debugCapture.generatedCodes),
                referenceCodes: debugCapture.referenceCodes.map(encodeInt32Tensor),
                referenceTextTokenIDs: encodeInt32Tensor(conditioning.conditioning.referenceTextTokenIDs),
                resolvedLanguage: conditioning.conditioning.resolvedLanguage,
                codecLanguageID: conditioning.conditioning.codecLanguageID,
            ),
        )
    }

    static func runDirectProbe(
        text: String,
        manifest: ProbeProfileManifest,
        profileDirectoryURL: URL,
        windowSeconds: Double,
        conditioningMode: ConditioningMode,
        outputStem: String,
    ) async throws -> CompareRun {
        guard let materialization = manifest.backendMaterializations.first(where: { $0.backend == "qwen3" }) else {
            throw UsageError.profileMissingQwenMaterialization(profileDirectoryURL.path)
        }

        let loadedModel = try await TTS.loadModel(modelRepo: materialization.modelRepo)
        guard let qwenModel = loadedModel as? Qwen3TTSModel else {
            throw UsageError.profileModelIsNotQwen(materialization.modelRepo)
        }

        var generationParameters = qwenModel.defaultGenerationParameters
        let wordCount = max(text.split(whereSeparator: \.isWhitespace).count, 1)
        generationParameters.maxTokens = min(2048, max(56, wordCount * 8))
        generationParameters.temperature = 0.9
        generationParameters.topP = 1.0
        generationParameters.repetitionPenalty = 1.05
        let directSamples: [Float]

        switch conditioningMode {
            case .artifact:
                guard let conditioningArtifact = try loadStoredConditioning(
                    manifest: manifest,
                    profileDirectoryURL: profileDirectoryURL,
                ) else {
                    throw UsageError.profileMissingStoredConditioning(profileDirectoryURL.path)
                }

                directSamples = try await qwenModel.generate(
                    text: text,
                    conditioning: conditioningArtifact,
                    generationParameters: generationParameters,
                )
                .asArray(Float.self)
            case .auto:
                if let conditioningArtifact = try loadStoredConditioning(
                    manifest: manifest,
                    profileDirectoryURL: profileDirectoryURL,
                ) {
                    directSamples = try await qwenModel.generate(
                        text: text,
                        conditioning: conditioningArtifact,
                        generationParameters: generationParameters,
                    )
                    .asArray(Float.self)
                } else {
                    let referenceAudioURL = profileDirectoryURL.appendingPathComponent(
                        materialization.referenceAudioFile,
                        isDirectory: false,
                    )
                    let refAudio = try loadReferenceAudio(at: referenceAudioURL, sampleRate: qwenModel.sampleRate)
                    directSamples = try await qwenModel.generate(
                        text: text,
                        voice: nil,
                        refAudio: refAudio,
                        refText: materialization.referenceText,
                        language: "English",
                        generationParameters: generationParameters,
                    )
                    .asArray(Float.self)
                }
            case .raw:
                let referenceAudioURL = profileDirectoryURL.appendingPathComponent(
                    materialization.referenceAudioFile,
                    isDirectory: false,
                )
                let refAudio = try loadReferenceAudio(at: referenceAudioURL, sampleRate: qwenModel.sampleRate)
                directSamples = try await qwenModel.generate(
                    text: text,
                    voice: nil,
                    refAudio: refAudio,
                    refText: materialization.referenceText,
                    language: "English",
                    generationParameters: generationParameters,
                )
                .asArray(Float.self)
        }

        let directOutputURL = try writeProbeWAV(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            name: "\(outputStem).wav",
        )
        let analysis = analyzeVolume(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            windowSeconds: windowSeconds,
        )

        return CompareRun(
            lane: "direct",
            conditioningMode: conditioningMode,
            generatedFilePath: directOutputURL.path,
            analysis: analysis,
        )
    }

    static func makeDirectConditioning(
        qwenModel: Qwen3TTSModel,
        manifest: ProbeProfileManifest,
        materialization: ProbeMaterializationManifest,
        profileDirectoryURL: URL,
        conditioningMode: ConditioningMode,
    ) throws -> (conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning, source: String) {
        switch conditioningMode {
            case .artifact:
                guard let conditioningArtifact = try loadStoredConditioning(
                    manifest: manifest,
                    profileDirectoryURL: profileDirectoryURL,
                ) else {
                    throw UsageError.profileMissingStoredConditioning(profileDirectoryURL.path)
                }

                return (conditioningArtifact, "artifact")
            case .auto:
                if let conditioningArtifact = try loadStoredConditioning(
                    manifest: manifest,
                    profileDirectoryURL: profileDirectoryURL,
                ) {
                    return (conditioningArtifact, "artifact")
                }
                fallthrough
            case .raw:
                let referenceAudioURL = profileDirectoryURL.appendingPathComponent(
                    materialization.referenceAudioFile,
                    isDirectory: false,
                )
                let refAudio = try loadReferenceAudio(at: referenceAudioURL, sampleRate: qwenModel.sampleRate)
                let rebuiltConditioning = try qwenModel.prepareReferenceConditioning(
                    refAudio: refAudio,
                    refText: materialization.referenceText,
                    language: "English",
                )
                return (rebuiltConditioning, "raw")
        }
    }

    static func replayArtifactURL(options: ReplayQwenCodesOptions) throws -> URL {
        if let artifactFile = options.artifactFile {
            return URL(fileURLWithPath: artifactFile, isDirectory: false)
        }

        return try packageRootURL()
            .appendingPathComponent(".local/volume-probes/capture-qwen-codes-latest.json", isDirectory: false)
    }

    static func loadCapturedQwenCodeArtifact(from url: URL) throws -> DecodableQwenCodeCaptureArtifact {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DecodableQwenCodeCaptureArtifact.self, from: data)
    }

    static func makeReplayDecodeCodes(
        generatedCodes: MLXArray,
        referenceCodes: MLXArray?,
    ) -> MLXArray {
        if let referenceCodes {
            return concatenated([referenceCodes.transposed(0, 2, 1), generatedCodes], axis: 1)
        }

        return generatedCodes
    }

    static func trimDecodedReferencePrefix(
        _ samples: [Float],
        generatedCodes: MLXArray,
        referenceCodes: MLXArray?,
    ) -> [Float] {
        guard let referenceCodes else { return samples }

        let totalLength = generatedCodes.dim(1) + referenceCodes.dim(2)
        let cut = Int(Double(referenceCodes.dim(2)) / Double(max(totalLength, 1)) * Double(samples.count))
        guard cut > 0, cut < samples.count else { return samples }

        return Array(samples[cut...])
    }

    static func makeReplayRun(
        lane: String,
        samples: [Float],
        sampleRate: Int,
        windowSeconds: Double,
        outputStem: String,
    ) throws -> CompareRun {
        let outputURL = try writeProbeWAV(
            samples: samples,
            sampleRate: sampleRate,
            name: "\(outputStem).wav",
        )
        let analysis = analyzeVolume(
            samples: samples,
            sampleRate: sampleRate,
            windowSeconds: windowSeconds,
        )
        return CompareRun(
            lane: lane,
            conditioningMode: .auto,
            generatedFilePath: outputURL.path,
            analysis: analysis,
        )
    }

    static func profileRootURL(options: VolumeProbeOptions) -> URL {
        profileRootURL(profileRootOverride: options.profileRoot)
    }

    static func probeProfileContext(
        profileName: String,
        profileRootOverride: String?,
    ) throws -> (profileDirectoryURL: URL, manifest: ProbeProfileManifest) {
        let profileDirectoryURL = profileRootURL(profileRootOverride: profileRootOverride)
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(profileName, isDirectory: true)
        let manifest = try loadProfileManifest(from: profileDirectoryURL)
        return (profileDirectoryURL, manifest)
    }

    static func validateConditioningMode(
        profileName: String,
        profileRootOverride: String?,
        conditioningMode: ConditioningMode,
    ) throws {
        guard conditioningMode == .artifact else { return }

        let (profileDirectoryURL, manifest) = try probeProfileContext(
            profileName: profileName,
            profileRootOverride: profileRootOverride,
        )
        guard try loadStoredConditioning(manifest: manifest, profileDirectoryURL: profileDirectoryURL) != nil else {
            throw UsageError.profileMissingStoredConditioning(profileDirectoryURL.path)
        }
    }

    static func profileRootURL(profileRootOverride: String?) -> URL {
        if let profileRootOverride {
            return URL(fileURLWithPath: profileRootOverride, isDirectory: true)
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
    }

    static func loadProfileManifest(from profileDirectoryURL: URL) throws -> ProbeProfileManifest {
        let manifestURL = profileDirectoryURL.appendingPathComponent("profile.json", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProbeProfileManifest.self, from: data)
    }

    static func loadStoredConditioning(
        manifest: ProbeProfileManifest,
        profileDirectoryURL: URL,
    ) throws -> Qwen3TTSModel.Qwen3TTSReferenceConditioning? {
        guard let artifactManifest = manifest.qwenConditioningArtifacts.first(where: { $0.backend == "qwen3" }) else {
            return nil
        }

        let artifactURL = profileDirectoryURL.appendingPathComponent(
            artifactManifest.artifactFile,
            isDirectory: false,
        )
        let data = try Data(contentsOf: artifactURL)
        let decoder = JSONDecoder()
        let artifact = try decoder.decode(ProbePersistedQwenConditioningArtifact.self, from: data)
        return artifact.makeConditioning()
    }

    static func loadReferenceAudio(at url: URL, sampleRate: Int) throws -> MLXArray {
        let (_, audio) = try MLXAudioCore.loadAudioArray(from: url, sampleRate: sampleRate)
        return audio
    }

    static func makeProbeText(repeatCount: Int) -> String {
        Array(repeating: defaultProbeParagraph, count: repeatCount).joined(separator: "\n\n")
    }

    static func loadMatrixText(textFile: String?, repeatCount: Int) throws -> String {
        if let textFile {
            let text = try String(contentsOfFile: textFile, encoding: .utf8)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw UsageError.emptyProbeText
            }

            return trimmed
        }

        return makeProbeText(repeatCount: repeatCount)
    }

    static func writeProbeWAV(
        samples: [Float],
        sampleRate: Int,
        name: String,
    ) throws -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("SpeakSwiftlyTesting", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try writeFloatWAV(samples: samples, sampleRate: sampleRate, to: url)
        return url
    }

    static func writeFloatWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        let channelCount = 1
        let bitsPerSample = 32
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * blockAlign
        let audioDataSize = samples.count * MemoryLayout<Float>.size
        let riffChunkSize = 4 + (8 + 16) + (8 + audioDataSize)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(riffChunkSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16, to: &data)
        appendUInt16(3, to: &data)
        appendUInt16(UInt16(channelCount), to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(byteRate), to: &data)
        appendUInt16(UInt16(blockAlign), to: &data)
        appendUInt16(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(audioDataSize), to: &data)

        samples.withUnsafeBufferPointer { buffer in
            data.append(contentsOf: UnsafeRawBufferPointer(buffer))
        }

        try data.write(to: url)
    }

    static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func analyzeVolume(
        at path: String,
        sampleRate: Int,
        windowSeconds: Double,
    ) throws -> ProbeAnalysis {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let wav = try parseFloatWAV(data)
        return analyzeVolume(
            samples: wav.samples,
            sampleRate: sampleRate,
            windowSeconds: windowSeconds,
        )
    }

    static func makeEncodableProbeAnalysis(_ analysis: ProbeAnalysis) -> EncodableProbeAnalysis {
        EncodableProbeAnalysis(
            sampleRate: analysis.sampleRate,
            windows: analysis.windows.map {
                EncodableVolumeWindow(
                    index: $0.index,
                    startSeconds: $0.startSeconds,
                    durationSeconds: $0.durationSeconds,
                    rms: $0.rms,
                    peak: $0.peak,
                )
            },
            summary: analysis.summary.map {
                EncodableVolumeSummary(
                    firstRMS: $0.firstRMS,
                    lastRMS: $0.lastRMS,
                    rmsDropPercent: $0.rmsDropPercent,
                    slopePerWindow: $0.slopePerWindow,
                    firstPeak: $0.firstPeak,
                    lastPeak: $0.lastPeak,
                    headRMS: $0.headRMS,
                    tailRMS: $0.tailRMS,
                    tailHeadRatio: $0.tailHeadRatio,
                    segments: $0.segments.map {
                        EncodableVolumeSegment(label: $0.label, rms: $0.rms, peak: $0.peak)
                    },
                )
            },
        )
    }

    static func makeCompareRunArtifact(_ run: CompareRun) -> CompareRunArtifact {
        CompareRunArtifact(
            lane: run.lane,
            conditioningMode: run.conditioningMode.rawValue,
            generatedFilePath: run.generatedFilePath,
            analysis: makeEncodableProbeAnalysis(run.analysis),
        )
    }

    static func encodeInt32Tensor(_ array: MLXArray) -> EncodableInt32Tensor {
        EncodableInt32Tensor(
            values: array.asArray(Int32.self),
            shape: array.shape,
        )
    }

    static func writeProbeArtifact(
        _ artifact: some Encodable,
        stem: String,
        latestFilename: String,
    ) throws -> URL {
        let artifactsRoot = try packageRootURL()
            .appendingPathComponent(".local/volume-probes", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let artifactURL = artifactsRoot.appendingPathComponent("\(stem)-\(stamp).json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(artifact)
        try encoded.write(to: artifactURL, options: .atomic)

        let latestURL = artifactsRoot.appendingPathComponent(latestFilename, isDirectory: false)
        try encoded.write(to: latestURL, options: .atomic)
        return artifactURL
    }

    static func packageRootURL() throws -> URL {
        let fileManager = FileManager.default
        var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let manifestURL = candidateURL.appendingPathComponent("Package.swift", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL != candidateURL else {
                throw UsageError.packageRootNotFound(#filePath)
            }

            candidateURL = parentURL
        }
    }

    static func analyzeVolume(
        samples: [Float],
        sampleRate: Int,
        windowSeconds: Double,
    ) -> ProbeAnalysis {
        let framesPerWindow = max(1, Int((Double(sampleRate) * windowSeconds).rounded()))
        var windows = [VolumeWindow]()
        windows.reserveCapacity(max(1, samples.count / framesPerWindow))

        var index = 0
        var start = 0
        while start < samples.count {
            let end = min(start + framesPerWindow, samples.count)
            let segment = Array(samples[start..<end])
            let durationSeconds = Double(segment.count) / Double(sampleRate)
            let rms = rootMeanSquare(segment)
            let peak = segment.map { abs($0) }.max() ?? 0
            windows.append(
                VolumeWindow(
                    index: index + 1,
                    startSeconds: Double(start) / Double(sampleRate),
                    durationSeconds: durationSeconds,
                    rms: rms,
                    peak: Double(peak),
                ),
            )
            index += 1
            start = end
        }

        return ProbeAnalysis(
            sampleRate: sampleRate,
            windows: windows,
            summary: summarizeWindows(windows),
        )
    }

    static func printAnalysis(
        _ analysis: ProbeAnalysis,
        prefix: String,
        summaryLabel: String,
    ) {
        for window in analysis.windows {
            print(
                String(
                    format: "%@_%02d: start=%.1fs duration=%.2fs rms=%.5f peak=%.5f",
                    prefix,
                    window.index,
                    window.startSeconds,
                    window.durationSeconds,
                    window.rms,
                    window.peak,
                ),
            )
        }

        if let summary = analysis.summary {
            print(
                String(
                    format: "%@: first_rms=%.5f last_rms=%.5f rms_drop_pct=%.2f slope_per_window=%.6f first_peak=%.5f last_peak=%.5f head_rms=%.5f tail_rms=%.5f tail_head_ratio=%.5f",
                    summaryLabel,
                    summary.firstRMS,
                    summary.lastRMS,
                    summary.rmsDropPercent,
                    summary.slopePerWindow,
                    summary.firstPeak,
                    summary.lastPeak,
                    summary.headRMS,
                    summary.tailRMS,
                    summary.tailHeadRatio,
                ),
            )
            for segment in summary.segments {
                print(
                    String(
                        format: "%@_%@: rms=%.5f peak=%.5f",
                        summaryLabel,
                        segment.label,
                        segment.rms,
                        segment.peak,
                    ),
                )
            }
        }
    }

    static func summarizeQwenCodes(_ tensor: ProbeInt32Tensor) throws -> QwenCodeArtifactStats {
        guard tensor.shape.count == 3, tensor.shape[0] == 1 else {
            throw UsageError.invalidWAV(
                "SpeakSwiftlyTesting expected generated Qwen codes to have shape [1, time, codebooks], but found \(tensor.shape).",
            )
        }

        let frameCount = tensor.shape[1]
        let codebookCount = tensor.shape[2]
        let totalTokenCount = tensor.values.count
        let quarterBounds = makeQuarterBounds(frameCount: frameCount)
        let quarterStats = quarterBounds.map { quarter in
            summarizeQwenCodeRange(
                tensor.values,
                frameCount: frameCount,
                codebookCount: codebookCount,
                startFrame: quarter.start,
                endFrame: quarter.end,
                label: quarter.label,
            )
        }

        let fullRange = summarizeQwenCodeRange(
            tensor.values,
            frameCount: frameCount,
            codebookCount: codebookCount,
            startFrame: 0,
            endFrame: frameCount,
            label: "full",
        )
        let headTail = summarizeQwenHeadTailShift(
            tensor.values,
            frameCount: frameCount,
            codebookCount: codebookCount,
        )

        return QwenCodeArtifactStats(
            frameCount: frameCount,
            codebookCount: codebookCount,
            totalTokenCount: totalTokenCount,
            distinctTokenCount: Set(tensor.values).count,
            exactAdjacentRepeatRatio: fullRange.exactAdjacentRepeatRatio,
            distinctTokensMeanPerCodebook: fullRange.distinctTokensMeanPerCodebook,
            distinctTokensMinPerCodebook: fullRange.distinctTokensMinPerCodebook,
            distinctTokensMaxPerCodebook: fullRange.distinctTokensMaxPerCodebook,
            longestRunMeanPerCodebook: fullRange.longestRunMeanPerCodebook,
            longestRunMaxPerCodebook: fullRange.longestRunMaxPerCodebook,
            headTailDistinctJaccardMean: headTail.jaccardMean,
            headTailDistinctJaccardMin: headTail.jaccardMin,
            headTailDistributionShiftMean: headTail.shiftMean,
            headTailDistributionShiftMax: headTail.shiftMax,
            quarters: quarterStats,
        )
    }

    static func compareQwenCodeTensors(
        _ left: ProbeInt32Tensor,
        _ right: ProbeInt32Tensor,
    ) throws -> QwenCodePairComparison {
        guard left.shape == right.shape else {
            throw UsageError.invalidWAV(
                "SpeakSwiftlyTesting expected both generated-code tensors to share the same shape for comparison, but found \(left.shape) and \(right.shape).",
            )
        }
        guard left.shape.count == 3, left.shape[0] == 1 else {
            throw UsageError.invalidWAV(
                "SpeakSwiftlyTesting expected generated Qwen codes to have shape [1, time, codebooks], but found \(left.shape).",
            )
        }

        let frameCount = left.shape[1]
        let codebookCount = left.shape[2]
        let totalTokenCount = left.values.count
        var exactMatches = 0
        var exactMatchesPerCodebook = Array(repeating: 0, count: codebookCount)
        let leftDistributions = qwenCodeDistributions(
            left.values,
            frameCount: frameCount,
            codebookCount: codebookCount,
            startFrame: 0,
            endFrame: frameCount,
        )
        let rightDistributions = qwenCodeDistributions(
            right.values,
            frameCount: frameCount,
            codebookCount: codebookCount,
            startFrame: 0,
            endFrame: frameCount,
        )

        for frame in 0..<frameCount {
            let base = frame * codebookCount
            for codebook in 0..<codebookCount {
                if left.values[base + codebook] == right.values[base + codebook] {
                    exactMatches += 1
                    exactMatchesPerCodebook[codebook] += 1
                }
            }
        }

        let exactMatchRatiosPerCodebook = exactMatchesPerCodebook.map { Double($0) / Double(frameCount) }
        let distributionJaccards = zip(leftDistributions, rightDistributions).map { pair in
            qwenCodeJaccard(pair.0, pair.1)
        }
        let distributionShifts = zip(leftDistributions, rightDistributions).map { pair in
            qwenCodeDistributionShift(pair.0, pair.1, sampleCount: frameCount)
        }

        return QwenCodePairComparison(
            exactPositionMatchRatio: Double(exactMatches) / Double(totalTokenCount),
            exactPositionMatchMinPerCodebook: exactMatchRatiosPerCodebook.min() ?? 0,
            exactPositionMatchMaxPerCodebook: exactMatchRatiosPerCodebook.max() ?? 0,
            fullSequenceDistinctJaccardMean: average(distributionJaccards),
            fullSequenceDistinctJaccardMin: distributionJaccards.min() ?? 0,
            fullSequenceDistributionShiftMean: average(distributionShifts),
            fullSequenceDistributionShiftMax: distributionShifts.max() ?? 0,
        )
    }

    static func printQwenCodeArtifactStats(_ stats: QwenCodeArtifactStats, prefix: String) {
        print(
            String(
                format: "%@_summary: frames=%d codebooks=%d tokens=%d distinct_tokens=%d repeat_ratio=%.5f distinct_mean=%.2f distinct_min=%d distinct_max=%d longest_run_mean=%.2f longest_run_max=%d head_tail_jaccard_mean=%.5f head_tail_jaccard_min=%.5f head_tail_shift_mean=%.5f head_tail_shift_max=%.5f",
                prefix,
                stats.frameCount,
                stats.codebookCount,
                stats.totalTokenCount,
                stats.distinctTokenCount,
                stats.exactAdjacentRepeatRatio,
                stats.distinctTokensMeanPerCodebook,
                stats.distinctTokensMinPerCodebook,
                stats.distinctTokensMaxPerCodebook,
                stats.longestRunMeanPerCodebook,
                stats.longestRunMaxPerCodebook,
                stats.headTailDistinctJaccardMean,
                stats.headTailDistinctJaccardMin,
                stats.headTailDistributionShiftMean,
                stats.headTailDistributionShiftMax,
            ),
        )

        for quarter in stats.quarters {
            print(
                String(
                    format: "%@_%@: frames=%d repeat_ratio=%.5f distinct_mean=%.2f distinct_min=%d distinct_max=%d longest_run_mean=%.2f longest_run_max=%d",
                    prefix,
                    quarter.label,
                    quarter.frameCount,
                    quarter.exactAdjacentRepeatRatio,
                    quarter.distinctTokensMeanPerCodebook,
                    quarter.distinctTokensMinPerCodebook,
                    quarter.distinctTokensMaxPerCodebook,
                    quarter.longestRunMeanPerCodebook,
                    quarter.longestRunMaxPerCodebook,
                ),
            )
        }
    }

    static func summarizeQwenCodeRange(
        _ values: [Int32],
        frameCount: Int,
        codebookCount: Int,
        startFrame: Int,
        endFrame: Int,
        label: String,
    ) -> QwenCodeQuarterStats {
        let clampedStart = max(0, min(startFrame, frameCount))
        let clampedEnd = max(clampedStart, min(endFrame, frameCount))
        let sampledFrames = clampedEnd - clampedStart
        guard sampledFrames > 0 else {
            return QwenCodeQuarterStats(
                label: label,
                frameCount: 0,
                exactAdjacentRepeatRatio: 0,
                distinctTokensMeanPerCodebook: 0,
                distinctTokensMinPerCodebook: 0,
                distinctTokensMaxPerCodebook: 0,
                longestRunMeanPerCodebook: 0,
                longestRunMaxPerCodebook: 0,
            )
        }

        var distinctSets = Array(repeating: Set<Int32>(), count: codebookCount)
        var longestRuns = Array(repeating: 1, count: codebookCount)
        var currentRuns = Array(repeating: 1, count: codebookCount)
        var repeatCount = 0

        for frame in clampedStart..<clampedEnd {
            let base = frame * codebookCount
            for codebook in 0..<codebookCount {
                let value = values[base + codebook]
                distinctSets[codebook].insert(value)
                if frame > clampedStart {
                    let previous = values[(frame - 1) * codebookCount + codebook]
                    if previous == value {
                        repeatCount += 1
                        currentRuns[codebook] += 1
                        longestRuns[codebook] = max(longestRuns[codebook], currentRuns[codebook])
                    } else {
                        currentRuns[codebook] = 1
                    }
                }
            }
        }

        let distinctCounts = distinctSets.map(\.count)
        let denominator = max((sampledFrames - 1) * codebookCount, 1)
        return QwenCodeQuarterStats(
            label: label,
            frameCount: sampledFrames,
            exactAdjacentRepeatRatio: sampledFrames > 1 ? Double(repeatCount) / Double(denominator) : 0,
            distinctTokensMeanPerCodebook: average(distinctCounts.map(Double.init)),
            distinctTokensMinPerCodebook: distinctCounts.min() ?? 0,
            distinctTokensMaxPerCodebook: distinctCounts.max() ?? 0,
            longestRunMeanPerCodebook: average(longestRuns.map(Double.init)),
            longestRunMaxPerCodebook: longestRuns.max() ?? 0,
        )
    }

    static func summarizeQwenHeadTailShift(
        _ values: [Int32],
        frameCount: Int,
        codebookCount: Int,
    ) -> (jaccardMean: Double, jaccardMin: Double, shiftMean: Double, shiftMax: Double) {
        let midpoint = max(frameCount / 2, 1)
        let head = qwenCodeDistributions(
            values,
            frameCount: frameCount,
            codebookCount: codebookCount,
            startFrame: 0,
            endFrame: midpoint,
        )
        let tail = qwenCodeDistributions(
            values,
            frameCount: frameCount,
            codebookCount: codebookCount,
            startFrame: midpoint,
            endFrame: frameCount,
        )
        let headFrames = midpoint
        let tailFrames = max(frameCount - midpoint, 1)
        let jaccards = zip(head, tail).map { pair in
            qwenCodeJaccard(pair.0, pair.1)
        }
        let shifts = zip(head, tail).map { pair in
            qwenCodeDistributionShift(
                pair.0,
                pair.1,
                sampleCountA: headFrames,
                sampleCountB: tailFrames,
            )
        }

        return (
            average(jaccards),
            jaccards.min() ?? 0,
            average(shifts),
            shifts.max() ?? 0,
        )
    }

    static func qwenCodeDistributions(
        _ values: [Int32],
        frameCount: Int,
        codebookCount: Int,
        startFrame: Int,
        endFrame: Int,
    ) -> [[Int32: Int]] {
        let clampedStart = max(0, min(startFrame, frameCount))
        let clampedEnd = max(clampedStart, min(endFrame, frameCount))
        var distributions = Array(repeating: [Int32: Int](), count: codebookCount)
        for frame in clampedStart..<clampedEnd {
            let base = frame * codebookCount
            for codebook in 0..<codebookCount {
                let value = values[base + codebook]
                distributions[codebook][value, default: 0] += 1
            }
        }
        return distributions
    }

    static func qwenCodeJaccard(_ left: [Int32: Int], _ right: [Int32: Int]) -> Double {
        guard !left.isEmpty || !right.isEmpty else { return 1 }

        let leftKeys = Set(left.keys)
        let rightKeys = Set(right.keys)
        let union = leftKeys.union(rightKeys)
        guard !union.isEmpty else { return 1 }

        return Double(leftKeys.intersection(rightKeys).count) / Double(union.count)
    }

    static func qwenCodeDistributionShift(
        _ left: [Int32: Int],
        _ right: [Int32: Int],
        sampleCount: Int,
    ) -> Double {
        qwenCodeDistributionShift(left, right, sampleCountA: sampleCount, sampleCountB: sampleCount)
    }

    static func qwenCodeDistributionShift(
        _ left: [Int32: Int],
        _ right: [Int32: Int],
        sampleCountA: Int,
        sampleCountB: Int,
    ) -> Double {
        guard sampleCountA > 0, sampleCountB > 0 else { return 0 }

        let keys = Set(left.keys).union(right.keys)
        let total = keys.reduce(into: 0.0) { partialResult, key in
            let leftProbability = Double(left[key] ?? 0) / Double(sampleCountA)
            let rightProbability = Double(right[key] ?? 0) / Double(sampleCountB)
            partialResult += abs(leftProbability - rightProbability)
        }
        return total / 2.0
    }

    static func makeQuarterBounds(frameCount: Int) -> [(label: String, start: Int, end: Int)] {
        let quarter = max(frameCount / 4, 1)
        let q1End = min(quarter, frameCount)
        let q2End = min(quarter * 2, frameCount)
        let q3End = min(quarter * 3, frameCount)
        return [
            ("q1", 0, q1End),
            ("q2", q1End, q2End),
            ("q3", q2End, q3End),
            ("q4", q3End, frameCount),
        ]
    }

    static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        return values.reduce(0, +) / Double(values.count)
    }

    static func rootMeanSquare(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }

        let sum = samples.reduce(into: 0.0) { partialResult, sample in
            let value = Double(sample)
            partialResult += value * value
        }
        return Foundation.sqrt(sum / Double(samples.count))
    }

    static func summarizeWindows(_ windows: [VolumeWindow]) -> VolumeSummary? {
        guard let first = windows.first, let last = windows.last else { return nil }

        let firstRMS = first.rms
        let lastRMS = last.rms
        let rmsDropPercent = firstRMS == 0 ? 0 : ((lastRMS - firstRMS) / firstRMS) * 100.0

        let xValues = windows.map { Double($0.index - 1) }
        let yValues = windows.map(\.rms)
        let xMean = xValues.reduce(0, +) / Double(xValues.count)
        let yMean = yValues.reduce(0, +) / Double(yValues.count)
        let numerator = zip(xValues, yValues).reduce(into: 0.0) { partialResult, pair in
            partialResult += (pair.0 - xMean) * (pair.1 - yMean)
        }
        let denominator = xValues.reduce(into: 0.0) { partialResult, x in
            let offset = x - xMean
            partialResult += offset * offset
        }
        let slopePerWindow = denominator == 0 ? 0 : numerator / denominator
        let segments = makeVolumeSegments(windows)
        let headRMS = segments.first?.rms ?? firstRMS
        let tailRMS = segments.last?.rms ?? lastRMS
        let tailHeadRatio = headRMS == 0 ? 0 : tailRMS / headRMS

        return VolumeSummary(
            firstRMS: firstRMS,
            lastRMS: lastRMS,
            rmsDropPercent: rmsDropPercent,
            slopePerWindow: slopePerWindow,
            firstPeak: first.peak,
            lastPeak: last.peak,
            headRMS: headRMS,
            tailRMS: tailRMS,
            tailHeadRatio: tailHeadRatio,
            segments: segments,
        )
    }

    static func makeVolumeSegments(_ windows: [VolumeWindow]) -> [VolumeSegment] {
        guard !windows.isEmpty else { return [] }

        let labels = ["q1", "q2", "q3", "q4"]
        let count = windows.count
        var segments = [VolumeSegment]()
        segments.reserveCapacity(labels.count)

        for (segmentIndex, label) in labels.enumerated() {
            let start = (segmentIndex * count) / labels.count
            let end = ((segmentIndex + 1) * count) / labels.count
            guard start < end else { continue }

            let segmentWindows = Array(windows[start..<end])
            let totalDuration = segmentWindows.reduce(0.0) { $0 + $1.durationSeconds }
            guard totalDuration > 0 else { continue }

            let weightedSquareSum = segmentWindows.reduce(0.0) { partialResult, window in
                partialResult + ((window.rms * window.rms) * window.durationSeconds)
            }
            let rms = Foundation.sqrt(weightedSquareSum / totalDuration)
            let peak = segmentWindows.map(\.peak).max() ?? 0
            segments.append(VolumeSegment(label: label, rms: rms, peak: peak))
        }

        return segments
    }

    static func parseFloatWAV(_ data: Data) throws -> (sampleRate: Int, channelCount: Int, samples: [Float]) {
        func uint16(at offset: Int) -> UInt16 {
            data.withUnsafeBytes { rawBuffer in
                rawBuffer.load(fromByteOffset: offset, as: UInt16.self)
            }
            .littleEndian
        }

        func uint32(at offset: Int) -> UInt32 {
            data.withUnsafeBytes { rawBuffer in
                rawBuffer.load(fromByteOffset: offset, as: UInt32.self)
            }
            .littleEndian
        }

        guard data.count >= 12 else {
            throw UsageError.invalidWAV("The generated file is too small to be a valid WAV container.")
        }
        guard String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
            throw UsageError.invalidWAV("The generated file is not a RIFF/WAVE container.")
        }

        var formatTag: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var audioPayload: Data?
        var offset = 12

        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let chunkSize = Int(uint32(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                throw UsageError.invalidWAV("A WAV chunk overruns the file boundary.")
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw UsageError.invalidWAV("The WAV fmt chunk is too small.")
                }

                formatTag = uint16(at: chunkStart)
                channelCount = uint16(at: chunkStart + 2)
                sampleRate = uint32(at: chunkStart + 4)
                bitsPerSample = uint16(at: chunkStart + 14)
            } else if chunkID == "data" {
                audioPayload = data[chunkStart..<chunkEnd]
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard formatTag == 3 else {
            throw UsageError.invalidWAV("SpeakSwiftlyTesting expected 32-bit float WAV output, but found format tag \(formatTag ?? 0).")
        }
        guard bitsPerSample == 32 else {
            throw UsageError.invalidWAV("SpeakSwiftlyTesting expected 32-bit float WAV output, but found \(bitsPerSample ?? 0) bits per sample.")
        }
        guard let resolvedChannelCount = channelCount, let resolvedSampleRate = sampleRate, let payload = audioPayload else {
            throw UsageError.invalidWAV("The WAV file is missing required fmt or data chunks.")
        }
        guard payload.count % 4 == 0 else {
            throw UsageError.invalidWAV("The WAV float payload is not aligned to 32-bit samples.")
        }

        let interleaved = payload.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }

        if resolvedChannelCount == 1 {
            return (
                sampleRate: Int(resolvedSampleRate),
                channelCount: Int(resolvedChannelCount),
                samples: interleaved,
            )
        }

        var mono = [Float]()
        mono.reserveCapacity(interleaved.count / Int(resolvedChannelCount))
        var sampleIndex = 0
        while sampleIndex < interleaved.count {
            mono.append(interleaved[sampleIndex])
            sampleIndex += Int(resolvedChannelCount)
        }

        return (
            sampleRate: Int(resolvedSampleRate),
            channelCount: Int(resolvedChannelCount),
            samples: mono,
        )
    }

    static func formatStatus(_ status: SpeakSwiftly.StatusEvent?) -> String {
        guard let status else {
            return "status payload missing"
        }

        return "stage=\(status.stage.rawValue) resident_state=\(status.residentState.rawValue) speech_backend=\(status.speechBackend.rawValue)"
    }
}

extension SpeakSwiftlyTestingMain {
    enum UsageError: LocalizedError {
        case missingCommand
        case unknownCommand(String)
        case unexpectedArguments(String)
        case missingOptionValue(String)
        case missingRequiredOption(String)
        case invalidOptionValue(String, String)
        case statusStreamEndedWithoutTerminalEvent
        case volumeProbeEndedWithoutGeneratedFile
        case createProfileEndedWithoutProfilePayload
        case emptyProbeText
        case invalidWAV(String)
        case profileMissingQwenMaterialization(String)
        case profileMissingStoredConditioning(String)
        case profileModelIsNotQwen(String)
        case qwenGeneratedCodesMissing(String)
        case referenceAudioLoadFailed(String)
        case packageRootNotFound(String)

        var errorDescription: String? {
            switch self {
                case .missingCommand:
                    usage
                case let .unknownCommand(command):
                    "Unknown SpeakSwiftlyTesting command '\(command)'.\n\(usage)"
                case let .unexpectedArguments(arguments):
                    "SpeakSwiftlyTesting received unexpected extra arguments: \(arguments).\n\(usage)"
                case let .missingOptionValue(option):
                    "SpeakSwiftlyTesting expected a value after '\(option)'.\n\(usage)"
                case let .missingRequiredOption(option):
                    "SpeakSwiftlyTesting requires option '\(option)' for this command.\n\(usage)"
                case let .invalidOptionValue(option, value):
                    "SpeakSwiftlyTesting could not use value '\(value)' for option '\(option)'.\n\(usage)"
                case .statusStreamEndedWithoutTerminalEvent:
                    "SpeakSwiftlyTesting watched the runtime status stream, but it ended before an acknowledged or completed status payload arrived."
                case .volumeProbeEndedWithoutGeneratedFile:
                    "SpeakSwiftlyTesting submitted a retained audio generation request, but the request stream ended before a generated file payload arrived."
                case .createProfileEndedWithoutProfilePayload:
                    "SpeakSwiftlyTesting submitted a voice-design profile creation request, but the request stream ended before a created profile payload arrived."
                case .emptyProbeText:
                    "SpeakSwiftlyTesting could not run the volume probe because the selected text input was empty after trimming whitespace."
                case let .invalidWAV(message):
                    message
                case let .profileMissingQwenMaterialization(path):
                    "SpeakSwiftlyTesting could not find a stored qwen3 backend materialization in '\(path)/profile.json'."
                case let .profileMissingStoredConditioning(path):
                    "SpeakSwiftlyTesting could not find a stored qwen3 conditioning artifact in '\(path)', but this probe run required explicit artifact conditioning."
                case let .profileModelIsNotQwen(modelRepo):
                    "SpeakSwiftlyTesting expected model repo '\(modelRepo)' to load as Qwen3TTSModel for the direct comparison path, but it resolved to a different speech model type."
                case let .qwenGeneratedCodesMissing(modelRepo):
                    "SpeakSwiftlyTesting expected the Qwen debug capture hook to return generated codec data for model repo '\(modelRepo)', but no generated-code payload arrived."
                case let .referenceAudioLoadFailed(path):
                    "SpeakSwiftlyTesting could not decode any audio samples from '\(path)' for the direct Qwen comparison path."
                case let .packageRootNotFound(path):
                    "SpeakSwiftlyTesting could not find the package root while walking upward from '\(path)' to write the local investigation artifact."
            }
        }

        var usage: String {
            """
            Usage:
              swift run SpeakSwiftlyTesting resources
              swift run SpeakSwiftlyTesting status
              swift run SpeakSwiftlyTesting smoke
              swift run SpeakSwiftlyTesting create-design-profile --profile NAME --voice DESCRIPTION [--text SOURCE] [--vibe femme|masc|neutral] [--profile-root PATH]
              swift run SpeakSwiftlyTesting volume-probe [--profile NAME] [--profile-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS] [--conditioning auto|raw|artifact]
              swift run SpeakSwiftlyTesting compare-volume [--profile NAME] [--profile-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS] [--conditioning auto|raw|artifact]
              swift run SpeakSwiftlyTesting matrix-volume [--profile NAME ...] [--profile-root PATH] [--short-text-file PATH] [--long-text-file PATH] [--short-repeat COUNT] [--long-repeat COUNT] [--iterations COUNT] [--window-seconds SECONDS] [--include-streamed]
              swift run SpeakSwiftlyTesting capture-qwen-codes [--profile NAME] [--profile-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS] [--conditioning auto|raw|artifact] [--lane direct]
              swift run SpeakSwiftlyTesting replay-qwen-codes [--artifact-file PATH] [--window-seconds SECONDS]
              swift run SpeakSwiftlyTesting compare-qwen-codes --left-artifact-file PATH --right-artifact-file PATH
            """
        }
    }
}
