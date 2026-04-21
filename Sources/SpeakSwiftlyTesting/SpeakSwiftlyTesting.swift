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
    }

    struct VolumeWindow {
        let index: Int
        let startSeconds: Double
        let durationSeconds: Double
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
    }

    struct ProbeAnalysis {
        let sampleRate: Int
        let windows: [VolumeWindow]
        let summary: VolumeSummary?
    }

    struct CompareRun {
        let generatedFilePath: String
        let analysis: ProbeAnalysis
    }

    struct ComparisonResult {
        let streamed: CompareRun
        let direct: CompareRun
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

    static let profileRootOverrideEnvironmentVariable = "SPEAKSWIFTLY_PROFILE_ROOT"

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

        let text = try loadVolumeProbeText(options: options)
        let result = try await runStreamedProbe(
            profileName: options.profileName,
            text: text,
            windowSeconds: options.windowSeconds,
        )

        print("profile_name: \(options.profileName)")
        if let profileRoot = options.profileRoot {
            print("profile_root: \(profileRoot)")
        }
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
    ) async throws -> CompareRun {
        let runtime = await SpeakSwiftly.liftoff()
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
            generatedFilePath: generatedFile.filePath,
            analysis: analysis,
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
        )
        let profileRootURL = profileRootURL(options: options)
        let profileDirectoryURL = profileRootURL
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(options.profileName, isDirectory: true)
        let manifest = try loadProfileManifest(from: profileDirectoryURL)
        let direct = try await runDirectProbe(
            text: text,
            manifest: manifest,
            profileDirectoryURL: profileDirectoryURL,
            windowSeconds: options.windowSeconds,
        )
        return ComparisonResult(streamed: streamed, direct: direct)
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
        let wordCount = max(text.split(whereSeparator: \.isWhitespace).count, 1)
        generationParameters.maxTokens = min(2048, max(56, wordCount * 8))
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
                language: "English",
                generationParameters: generationParameters,
            )
            .asArray(Float.self)
        }

        let directOutputURL = try writeProbeWAV(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            name: "qwen-direct-volume-probe.wav",
        )
        let analysis = analyzeVolume(
            samples: directSamples,
            sampleRate: qwenModel.sampleRate,
            windowSeconds: windowSeconds,
        )

        return CompareRun(
            generatedFilePath: directOutputURL.path,
            analysis: analysis,
        )
    }

    static func profileRootURL(options: VolumeProbeOptions) -> URL {
        if let profileRoot = options.profileRoot {
            return URL(fileURLWithPath: profileRoot, isDirectory: true)
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
                    format: "%@: first_rms=%.5f last_rms=%.5f rms_drop_pct=%.2f slope_per_window=%.6f first_peak=%.5f last_peak=%.5f",
                    summaryLabel,
                    summary.firstRMS,
                    summary.lastRMS,
                    summary.rmsDropPercent,
                    summary.slopePerWindow,
                    summary.firstPeak,
                    summary.lastPeak,
                ),
            )
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

        return VolumeSummary(
            firstRMS: firstRMS,
            lastRMS: lastRMS,
            rmsDropPercent: rmsDropPercent,
            slopePerWindow: slopePerWindow,
            firstPeak: first.peak,
            lastPeak: last.peak,
        )
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
        case profileModelIsNotQwen(String)
        case referenceAudioLoadFailed(String)

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
                case let .profileModelIsNotQwen(modelRepo):
                    "SpeakSwiftlyTesting expected model repo '\(modelRepo)' to load as Qwen3TTSModel for the direct comparison path, but it resolved to a different speech model type."
                case let .referenceAudioLoadFailed(path):
                    "SpeakSwiftlyTesting could not decode any audio samples from '\(path)' for the direct Qwen comparison path."
            }
        }

        var usage: String {
            """
            Usage:
              swift run SpeakSwiftlyTesting resources
              swift run SpeakSwiftlyTesting status
              swift run SpeakSwiftlyTesting smoke
              swift run SpeakSwiftlyTesting create-design-profile --profile NAME --voice DESCRIPTION [--text SOURCE] [--vibe femme|masc|neutral] [--profile-root PATH]
              swift run SpeakSwiftlyTesting volume-probe [--profile NAME] [--profile-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS]
              swift run SpeakSwiftlyTesting compare-volume [--profile NAME] [--profile-root PATH] [--text-file PATH] [--repeat COUNT] [--window-seconds SECONDS]
            """
        }
    }
}
