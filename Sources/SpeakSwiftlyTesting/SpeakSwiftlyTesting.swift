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
            """
        }
    }
}
