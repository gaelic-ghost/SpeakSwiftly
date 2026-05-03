import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS
import SpeakSwiftly
import SpeakSwiftlyTestingSupport

@main
struct SpeakSwiftlyTestingMain {
    enum Command: String {
        case resources
        case status
        case smoke
        case createDesignProfile = "create-design-profile"
        case volumeProbe = "volume-probe"
        case compareVolume = "compare-volume"
    }

    struct CreateDesignProfileOptions {
        var profileName: String
        var sourceText = "Hello there from SpeakSwiftly end-to-end coverage."
        var vibe = "femme"
        var voiceDescription: String
        var stateRoot: String?
    }

    struct VolumeProbeOptions {
        var profileName = "default-femme"
        var stateRoot: String?
        var textFile: String?
        var repeatCount = 10
        var windowSeconds = 2.0
        var matchedDurationMode = MatchedDurationMode.refuse
    }

    enum MatchedDurationMode: String, Codable {
        case refuse
        case trimToShorter = "trim-to-shorter"
    }

    struct CompareRun {
        let generatedFilePath: String
        let fullAnalysis: ProbeAnalysis
        let comparedAnalysis: ProbeAnalysis
    }

    struct ComparisonResult {
        let streamed: CompareRun
        let direct: CompareRun
        let matchedDurationMode: MatchedDurationMode
        let comparisonSampleCount: Int
    }

    struct VolumeProbeArtifact: Codable {
        let schemaVersion: Int
        let toolName: String
        let sourceSurface: String
        let profileName: String
        let stateRoot: String?
        let textCharacters: Int
        let textWords: Int
        let textFingerprint: String
        let generatedFilePath: String
        let analysis: ProbeAnalysis
    }

    struct CompareVolumeArtifact: Codable {
        let schemaVersion: Int
        let toolName: String
        let profileName: String
        let stateRoot: String?
        let textCharacters: Int
        let textWords: Int
        let textFingerprint: String
        let matchedDurationMode: MatchedDurationMode
        let comparisonSampleCount: Int
        let streamedGeneratedFilePath: String
        let directGeneratedFilePath: String
        let streamedFullAnalysis: ProbeAnalysis
        let directFullAnalysis: ProbeAnalysis
        let streamedComparedAnalysis: ProbeAnalysis
        let directComparedAnalysis: ProbeAnalysis
    }

    struct ProbeProfileManifest: Decodable {
        let backendMaterializations: [ProbeMaterializationManifest]
        let qwenConditioningArtifacts: [ProbeConditioningArtifactManifest]
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
                case "--state-root":
                    index += 1
                    options.stateRoot = try requireOptionValue(arguments, index: index, for: argument)
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
                case "--state-root":
                    index += 1
                    options.stateRoot = try requireOptionValue(arguments, index: index, for: argument)
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
                case "--matched-duration":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let mode = MatchedDurationMode(rawValue: value) else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.matchedDurationMode = mode
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
        print("request_kind: \(handle.kind.rawValue)")

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
                case let .completed(completion):
                    if case let .runtimeStatus(status, _) = completion {
                        print("completed: \(formatStatus(status))")
                    } else {
                        print("completed: no status payload")
                    }
                    return
            }
        }

        throw UsageError.statusStreamEndedWithoutTerminalEvent
    }

    static func runVolumeProbe(options: VolumeProbeOptions) async throws {
        let text = try loadVolumeProbeText(options: options)
        let result = try await runStreamedProbe(
            profileName: options.profileName,
            text: text,
            windowSeconds: options.windowSeconds,
            stateRootURL: stateRootURL(options: options),
        )

        print("profile_name: \(options.profileName)")
        if let stateRoot = options.stateRoot {
            print("state_root: \(stateRoot)")
        }
        print("text_characters: \(text.count)")
        print("text_words: \(text.split(whereSeparator: \.isWhitespace).count)")
        print("generated_file: \(result.generatedFilePath)")
        print("sample_rate: \(result.fullAnalysis.sampleRate)")
        print("window_seconds: \(result.fullAnalysis.windowSeconds)")

        printAnalysis(result.fullAnalysis, prefix: "window", summaryLabel: "summary")

        let artifact = VolumeProbeArtifact(
            schemaVersion: 1,
            toolName: "volume-probe",
            sourceSurface: "retained-file",
            profileName: options.profileName,
            stateRoot: options.stateRoot,
            textCharacters: text.count,
            textWords: text.split(whereSeparator: \.isWhitespace).count,
            textFingerprint: fingerprint(text),
            generatedFilePath: result.generatedFilePath,
            analysis: result.fullAnalysis,
        )
        let artifactPath = try writeProbeArtifact(artifact, stem: "volume-probe")
        print("artifact_file: \(artifactPath)")
    }

    static func runCreateDesignProfile(options: CreateDesignProfileOptions) async throws {
        let vibe = try parseVibe(options.vibe)
        let runtime = await SpeakSwiftly.liftoff(stateRootURL: stateRootURL(options: options))
        await runtime.start()
        let handle = await runtime.voices.create(
            design: options.profileName,
            from: options.sourceText,
            vibe: vibe,
            voiceDescription: options.voiceDescription,
        )
        let created = try await awaitCreatedProfile(from: handle)

        print("profile_name: \(created.profileName)")
        print("profile_path: \(created.profilePath)")
        print("source_text: \(options.sourceText)")
        print("voice_description: \(options.voiceDescription)")
        print("vibe: \(vibe.rawValue)")
        if let stateRoot = options.stateRoot {
            print("state_root: \(stateRoot)")
        }
    }

    static func runCompareVolume(options: VolumeProbeOptions) async throws {
        let text = try loadVolumeProbeText(options: options)
        let comparison = try await compareVolume(options: options, text: text)

        print("profile_name: \(options.profileName)")
        if let stateRoot = options.stateRoot {
            print("state_root: \(stateRoot)")
        }
        print("text_characters: \(text.count)")
        print("text_words: \(text.split(whereSeparator: \.isWhitespace).count)")
        print("window_seconds: \(options.windowSeconds)")
        print("streamed_generated_file: \(comparison.streamed.generatedFilePath)")
        print("streamed_sample_rate: \(comparison.streamed.fullAnalysis.sampleRate)")
        print("direct_generated_file: \(comparison.direct.generatedFilePath)")
        print("direct_sample_rate: \(comparison.direct.fullAnalysis.sampleRate)")
        print("matched_duration_mode: \(comparison.matchedDurationMode.rawValue)")
        print("comparison_sample_count: \(comparison.comparisonSampleCount)")

        printAnalysis(
            comparison.streamed.comparedAnalysis,
            prefix: "streamed_window",
            summaryLabel: "streamed_summary",
        )
        printAnalysis(
            comparison.direct.comparedAnalysis,
            prefix: "direct_window",
            summaryLabel: "direct_summary",
        )

        if let streamedSummary = comparison.streamed.comparedAnalysis.summary,
           let directSummary = comparison.direct.comparedAnalysis.summary {
            print(
                String(
                    format: "comparison: streamed_last_rms=%.5f direct_last_rms=%.5f streamed_endpoint_rms_delta_pct=%.2f direct_endpoint_rms_delta_pct=%.2f endpoint_delta_gap_pct=%.2f streamed_slope=%.6f direct_slope=%.6f",
                    streamedSummary.lastRMS,
                    directSummary.lastRMS,
                    streamedSummary.endpointRMSDeltaPercent,
                    directSummary.endpointRMSDeltaPercent,
                    streamedSummary.endpointRMSDeltaPercent - directSummary.endpointRMSDeltaPercent,
                    streamedSummary.slopePerWindow,
                    directSummary.slopePerWindow,
                ),
            )
        }

        let artifact = CompareVolumeArtifact(
            schemaVersion: 1,
            toolName: "compare-volume",
            profileName: options.profileName,
            stateRoot: options.stateRoot,
            textCharacters: text.count,
            textWords: text.split(whereSeparator: \.isWhitespace).count,
            textFingerprint: fingerprint(text),
            matchedDurationMode: comparison.matchedDurationMode,
            comparisonSampleCount: comparison.comparisonSampleCount,
            streamedGeneratedFilePath: comparison.streamed.generatedFilePath,
            directGeneratedFilePath: comparison.direct.generatedFilePath,
            streamedFullAnalysis: comparison.streamed.fullAnalysis,
            directFullAnalysis: comparison.direct.fullAnalysis,
            streamedComparedAnalysis: comparison.streamed.comparedAnalysis,
            directComparedAnalysis: comparison.direct.comparedAnalysis,
        )
        let artifactPath = try writeProbeArtifact(artifact, stem: "compare-volume")
        print("artifact_file: \(artifactPath)")
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

        let paragraph = """
        This is a long-form loudness probe for SpeakSwiftly. Please keep the voice steady, natural, and evenly projected from beginning to end. We are intentionally using a much longer passage so we can inspect whether the waveform stays consistent over time or gradually loses energy. The content itself is not important. What matters is that the generated speech remains stable, full, and equally audible throughout the entire passage, even after many seconds of continuous synthesis.
        """

        return Array(repeating: paragraph, count: options.repeatCount).joined(separator: "\n\n")
    }

    static func awaitGeneratedFile(
        from handle: SpeakSwiftly.RequestHandle,
    ) async throws -> SpeakSwiftly.GeneratedFile {
        for try await event in handle.events {
            switch event {
                case .queued, .started, .progress:
                    continue
                case let .acknowledged(success):
                    if let generatedFile = success.generatedFile {
                        return generatedFile
                    }
                case let .completed(completion):
                    if case let .generatedFile(generatedFile) = completion {
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
                case let .acknowledged(success):
                    if let profileName = success.profileName, let profilePath = success.profilePath {
                        return (profileName, profilePath)
                    }
                case let .completed(completion):
                    if case let .voiceProfile(profileName, profilePath) = completion,
                       let profileName,
                       let profilePath {
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
        stateRootURL: URL?,
    ) async throws -> CompareRun {
        let runtime = await SpeakSwiftly.liftoff(stateRootURL: stateRootURL)
        await runtime.start()

        let handle = await runtime.generate.audio(
            text: text,
            voiceProfile: profileName,
        )

        let generatedFile = try await awaitGeneratedFile(from: handle)
        let analysis = try analyzeVolume(
            at: generatedFile.filePath,
            windowSeconds: windowSeconds,
        )

        return CompareRun(
            generatedFilePath: generatedFile.filePath,
            fullAnalysis: analysis,
            comparedAnalysis: analysis,
        )
    }

    static func compareVolume(
        options: VolumeProbeOptions,
        text: String,
    ) async throws -> ComparisonResult {
        let streamed = try await runStreamedProbe(
            profileName: options.profileName,
            text: text,
            windowSeconds: options.windowSeconds,
            stateRootURL: stateRootURL(options: options),
        )
        let stateRootURL = resolvedStateRootURL(options: options)
        let profileDirectoryURL = stateRootURL
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(options.profileName, isDirectory: true)
        let manifest = try loadProfileManifest(from: profileDirectoryURL)
        let direct = try await runDirectProbe(
            text: text,
            manifest: manifest,
            profileDirectoryURL: profileDirectoryURL,
            windowSeconds: options.windowSeconds,
        )
        return try alignComparison(
            streamed: streamed,
            direct: direct,
            mode: options.matchedDurationMode,
            windowSeconds: options.windowSeconds,
        )
    }

    static func alignComparison(
        streamed: CompareRun,
        direct: CompareRun,
        mode: MatchedDurationMode,
        windowSeconds: Double,
    ) throws -> ComparisonResult {
        guard streamed.fullAnalysis.sampleRate == direct.fullAnalysis.sampleRate else {
            throw UsageError.comparisonSampleRateMismatch(
                streamed.fullAnalysis.sampleRate,
                direct.fullAnalysis.sampleRate,
            )
        }

        let streamedCount = streamed.fullAnalysis.sampleCount
        let directCount = direct.fullAnalysis.sampleCount
        guard streamedCount == directCount else {
            switch mode {
                case .refuse:
                    throw UsageError.comparisonDurationMismatch(
                        streamedCount,
                        directCount,
                        streamed.fullAnalysis.sampleRate,
                    )
                case .trimToShorter:
                    let comparisonSampleCount = min(streamedCount, directCount)
                    let streamedAnalysis = try analyzeVolume(
                        at: streamed.generatedFilePath,
                        windowSeconds: windowSeconds,
                        maxSampleCount: comparisonSampleCount,
                    )
                    let directAnalysis = try analyzeVolume(
                        at: direct.generatedFilePath,
                        windowSeconds: windowSeconds,
                        maxSampleCount: comparisonSampleCount,
                    )
                    return ComparisonResult(
                        streamed: CompareRun(
                            generatedFilePath: streamed.generatedFilePath,
                            fullAnalysis: streamed.fullAnalysis,
                            comparedAnalysis: streamedAnalysis,
                        ),
                        direct: CompareRun(
                            generatedFilePath: direct.generatedFilePath,
                            fullAnalysis: direct.fullAnalysis,
                            comparedAnalysis: directAnalysis,
                        ),
                        matchedDurationMode: mode,
                        comparisonSampleCount: comparisonSampleCount,
                    )
            }
        }

        return ComparisonResult(
            streamed: streamed,
            direct: direct,
            matchedDurationMode: mode,
            comparisonSampleCount: streamedCount,
        )
    }

    static func runDirectProbe(
        text: String,
        manifest: ProbeProfileManifest,
        profileDirectoryURL: URL,
        windowSeconds: Double,
    ) async throws -> CompareRun {
        guard let materialization = manifest.backendMaterializations.first(where: { $0.backend == "qwen3" }) else {
            throw UsageError.profileMissingQwenMaterialization(profileDirectoryURL.path)
        }

        let loadedModel = try await TTS.loadModel(modelRepo: materialization.modelRepo)
        guard let qwenModel = loadedModel as? Qwen3TTSModel else {
            throw UsageError.profileModelIsNotQwen(materialization.modelRepo)
        }

        var generationParameters = qwenModel.defaultGenerationParameters
        generationParameters.temperature = 0.9
        generationParameters.topP = 1.0
        generationParameters.repetitionPenalty = 1.05
        let directSamples: [Float]

        if let conditioningArtifact = try loadStoredConditioning(manifest: manifest, profileDirectoryURL: profileDirectoryURL) {
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
                language: nil,
                generationParameters: generationParameters,
            )
            .asArray(Float.self)
        }

        let directOutputURL = try writeProbeWAV(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            name: "qwen-direct-volume-probe-\(UUID().uuidString).wav",
        )
        let analysis = try analyzeVolume(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            windowSeconds: windowSeconds,
        )

        return CompareRun(
            generatedFilePath: directOutputURL.path,
            fullAnalysis: analysis,
            comparedAnalysis: analysis,
        )
    }

    static func resolvedStateRootURL(options: VolumeProbeOptions) -> URL {
        if let stateRoot = options.stateRoot {
            return URL(fileURLWithPath: stateRoot, isDirectory: true)
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
    }

    static func stateRootURL(options: CreateDesignProfileOptions) -> URL? {
        options.stateRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func stateRootURL(options: VolumeProbeOptions) -> URL? {
        options.stateRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
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

    static func printAnalysis(
        _ analysis: ProbeAnalysis,
        prefix: String,
        summaryLabel: String,
    ) {
        print(
            String(
                format: "%@: duration=%.3fs analyzed_duration=%.3fs sample_count=%d analyzed_sample_count=%d window_seconds=%.3f window_count=%d",
                summaryLabel,
                analysis.durationSeconds,
                Double(analysis.analyzedSampleCount) / Double(analysis.sampleRate),
                analysis.sampleCount,
                analysis.analyzedSampleCount,
                analysis.windowSeconds,
                analysis.windows.count,
            ),
        )

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
                    format: "%@: first_rms=%.5f last_rms=%.5f endpoint_rms_delta_pct=%.2f slope_per_window=%.6f head_rms=%.5f tail_rms=%.5f tail_head_ratio=%.5f last_%d_window_avg_rms=%.5f first_peak=%.5f last_peak=%.5f",
                    summaryLabel,
                    summary.firstRMS,
                    summary.lastRMS,
                    summary.endpointRMSDeltaPercent,
                    summary.slopePerWindow,
                    summary.headRMS,
                    summary.tailRMS,
                    summary.tailHeadRatio,
                    summary.lastWindowAverageCount,
                    summary.lastWindowAverageRMS,
                    summary.firstPeak,
                    summary.lastPeak,
                ),
            )
            for bucket in summary.buckets {
                print(
                    String(
                        format: "%@_%@: windows=%d-%d average_rms=%.5f average_peak=%.5f",
                        summaryLabel,
                        bucket.label,
                        bucket.startWindow,
                        bucket.endWindow,
                        bucket.averageRMS,
                        bucket.averagePeak,
                    ),
                )
            }
        }
    }

    static func writeProbeArtifact(_ artifact: some Encodable, stem: String) throws -> String {
        let directory = try probeArtifactDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let artifactURL = directory.appendingPathComponent("\(stem)-\(timestamp)-\(UUID().uuidString).json", isDirectory: false)
        let latestURL = directory.appendingPathComponent("\(stem)-latest.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(artifact)
        try data.write(to: artifactURL, options: .atomic)
        try data.write(to: latestURL, options: .atomic)
        return artifactURL.path
    }

    static func probeArtifactDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("volume-probes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func fingerprint(_ text: String) -> String {
        let bytes = Array(text.utf8)
        let offset: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let value = bytes.reduce(offset) { partialResult, byte in
            (partialResult ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", value)
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
        case profileMissingQwenMaterialization(String)
        case profileModelIsNotQwen(String)
        case referenceAudioLoadFailed(String)
        case comparisonSampleRateMismatch(Int, Int)
        case comparisonDurationMismatch(Int, Int, Int)

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
                case let .profileMissingQwenMaterialization(path):
                    "SpeakSwiftlyTesting could not find a stored qwen3 backend materialization in '\(path)/profile.json'."
                case let .profileModelIsNotQwen(modelRepo):
                    "SpeakSwiftlyTesting expected model repo '\(modelRepo)' to load as Qwen3TTSModel for the direct comparison path, but it resolved to a different speech model type."
                case let .referenceAudioLoadFailed(path):
                    "SpeakSwiftlyTesting could not decode any audio samples from '\(path)' for the direct Qwen comparison path."
                case let .comparisonSampleRateMismatch(streamed, direct):
                    "SpeakSwiftlyTesting refused compare-volume because the retained-file path used sample rate \(streamed), but the direct path used sample rate \(direct). The two runs are not like-for-like."
                case let .comparisonDurationMismatch(streamed, direct, sampleRate):
                    "SpeakSwiftlyTesting refused compare-volume because the retained-file path analyzed \(streamed) samples and the direct path analyzed \(direct) samples at \(sampleRate) Hz. Use '--matched-duration trim-to-shorter' only when you explicitly want both sides trimmed to the same analyzed span."
            }
        }

        var usage: String {
            """
            Usage:
              swift run SpeakSwiftlyTesting resources
              swift run SpeakSwiftlyTesting status
              swift run SpeakSwiftlyTesting smoke
              swift run SpeakSwiftlyTesting create-design-profile --profile NAME --voice DESCRIPTION [--text SOURCE] [--vibe femme|masc|neutral] [--state-root PATH]
              swift run SpeakSwiftlyTesting volume-probe [--profile NAME] [--state-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS]
              swift run SpeakSwiftlyTesting compare-volume [--profile NAME] [--state-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS] [--matched-duration refuse|trim-to-shorter]
            """
        }
    }
}
