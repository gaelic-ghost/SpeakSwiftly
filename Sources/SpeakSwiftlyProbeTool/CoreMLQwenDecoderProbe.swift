import CoreML
import Foundation

extension SpeakSwiftlyProbeToolMain {
    struct CoreMLQwenDecoderOptions {
        var modelPackage: String?
        var talkerCodeFixture: String?
        var sampleID: String?
        var computeUnits = "all"
        var warmupRuns = 1
        var measuredRuns = 5
        var output: String?
    }

    struct CoreMLQwenDecoderReport: Encodable {
        struct Source: Encodable {
            let modelPackage: String
            let talkerCodeFixture: String
            let sampleID: String
            let computeUnits: String
        }

        struct Sample: Encodable {
            let id: String
            let text: String?
            let audioCodesShape: [Int]
            let paddedInputShape: [Int]
            let paddedStepCount: Int
            let padValue: Int32
            let validOutputSampleCount: Int
            let paddedOutputSampleCount: Int
        }

        struct TimingStats: Encodable {
            let minMs: Double
            let medianMs: Double
            let meanMs: Double
            let p95Ms: Double
            let maxMs: Double
        }

        struct AudioSummary: Encodable {
            let sampleCount: Int
            let min: Float
            let max: Float
            let mean: Double
            let rms: Double
        }

        struct Prediction: Encodable {
            let compileDurationMs: Double?
            let loadDurationMs: Double
            let warmupRuns: Int
            let measuredRuns: Int
            let warmup: TimingStats?
            let measured: TimingStats
            let outputShape: [Int]
            let outputDataType: String
            let fullOutput: AudioSummary
            let validOutput: AudioSummary
            let paddedTail: AudioSummary?
        }

        let schemaVersion: Int
        let toolName: String
        let createdAtUTC: String
        let source: Source
        let sample: Sample
        let prediction: Prediction
    }

    struct CoreMLQwenTalkerFixture: Decodable {
        struct Sample: Decodable {
            struct Encoded: Decodable {
                let audioCodes: [[Int32]]
            }

            struct BucketAssignment: Decodable {
                let assignedBucket: Int
                let padValue: Int32
                let validOutputSampleCount: Int
                let paddedOutputSampleCount: Int
            }

            let id: String
            let text: String?
            let encoded: Encoded
            let bucketAssignment: BucketAssignment
        }

        let samples: [Sample]
    }

    struct CoreMLQwenPaddedCodes {
        let sample: CoreMLQwenTalkerFixture.Sample
        let inputShape: [Int]
        let values: [Int32]
        let paddedStepCount: Int
    }

    struct CoreMLQwenProbeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func parseCoreMLQwenDecoderOptions(arguments: [String]) throws -> CoreMLQwenDecoderOptions {
        var options = CoreMLQwenDecoderOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--model-package":
                    index += 1
                    options.modelPackage = try requireOptionValue(arguments, index: index, for: argument)
                case "--talker-code-fixture":
                    index += 1
                    options.talkerCodeFixture = try requireOptionValue(arguments, index: index, for: argument)
                case "--sample-id":
                    index += 1
                    options.sampleID = try requireOptionValue(arguments, index: index, for: argument)
                case "--compute-units":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard coreMLComputeUnits(named: value) != nil else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.computeUnits = value
                case "--warmup-runs":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let runs = Int(value), runs >= 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.warmupRuns = runs
                case "--measured-runs":
                    index += 1
                    let value = try requireOptionValue(arguments, index: index, for: argument)
                    guard let runs = Int(value), runs > 0 else {
                        throw UsageError.invalidOptionValue(argument, value)
                    }

                    options.measuredRuns = runs
                case "--output":
                    index += 1
                    options.output = try requireOptionValue(arguments, index: index, for: argument)
                default:
                    throw UsageError.unknownCommand(argument)
            }
            index += 1
        }

        guard options.modelPackage != nil else {
            throw UsageError.missingRequiredOption("--model-package")
        }
        guard options.talkerCodeFixture != nil else {
            throw UsageError.missingRequiredOption("--talker-code-fixture")
        }
        guard options.sampleID != nil else {
            throw UsageError.missingRequiredOption("--sample-id")
        }

        return options
    }

    static func runCoreMLQwenDecoderProbe(options: CoreMLQwenDecoderOptions) throws {
        let modelPackage = try requiredPath(options.modelPackage, label: "--model-package")
        let talkerCodeFixture = try requiredPath(options.talkerCodeFixture, label: "--talker-code-fixture")
        let sampleID = try requiredValue(options.sampleID, label: "--sample-id")
        let computeUnits = try requiredComputeUnits(options.computeUnits)
        let paddedCodes = try loadPaddedTalkerCodes(fixturePath: talkerCodeFixture, sampleID: sampleID)
        let compiledModel = try compileModelIfNeeded(at: URL(fileURLWithPath: modelPackage))

        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits

        let loadStart = monotonicMilliseconds()
        let model = try MLModel(contentsOf: compiledModel.url, configuration: configuration)
        let loadDurationMs = monotonicMilliseconds() - loadStart

        let input = try makeAudioCodesMultiArray(paddedCodes)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["audio_codes": input])
        var warmupDurations = [Double]()
        for _ in 0..<options.warmupRuns {
            try warmupDurations.append(predict(model: model, provider: provider).durationMs)
        }

        var measuredDurations = [Double]()
        var lastOutput: MLMultiArray?
        for _ in 0..<options.measuredRuns {
            let result = try predict(model: model, provider: provider)
            measuredDurations.append(result.durationMs)
            lastOutput = result.audioValues
        }

        let audioValues = try requireOutputValues(lastOutput)
        let allSamples = arrayValues(audioValues)
        let validCount = paddedCodes.sample.bucketAssignment.validOutputSampleCount
        let validSamples = Array(allSamples.prefix(validCount))
        let tailSamples = Array(allSamples.dropFirst(validCount))

        let report = try CoreMLQwenDecoderReport(
            schemaVersion: 1,
            toolName: "coreml-qwen-decoder",
            createdAtUTC: ISO8601DateFormatter().string(from: Date()),
            source: .init(
                modelPackage: modelPackage,
                talkerCodeFixture: talkerCodeFixture,
                sampleID: sampleID,
                computeUnits: options.computeUnits,
            ),
            sample: .init(
                id: paddedCodes.sample.id,
                text: paddedCodes.sample.text,
                audioCodesShape: [
                    paddedCodes.sample.encoded.audioCodes.count,
                    paddedCodes.sample.encoded.audioCodes.first?.count ?? 0,
                ],
                paddedInputShape: paddedCodes.inputShape,
                paddedStepCount: paddedCodes.paddedStepCount,
                padValue: paddedCodes.sample.bucketAssignment.padValue,
                validOutputSampleCount: paddedCodes.sample.bucketAssignment.validOutputSampleCount,
                paddedOutputSampleCount: paddedCodes.sample.bucketAssignment.paddedOutputSampleCount,
            ),
            prediction: .init(
                compileDurationMs: compiledModel.compileDurationMs,
                loadDurationMs: loadDurationMs,
                warmupRuns: options.warmupRuns,
                measuredRuns: options.measuredRuns,
                warmup: timingStats(warmupDurations),
                measured: requiredTimingStats(measuredDurations),
                outputShape: audioValues.shape.map(\.intValue),
                outputDataType: "\(audioValues.dataType)",
                fullOutput: audioSummary(allSamples),
                validOutput: audioSummary(validSamples),
                paddedTail: tailSamples.isEmpty ? nil : audioSummary(tailSamples),
            ),
        )

        try writeCoreMLQwenDecoderReport(report, output: options.output)
    }

    static func compileModelIfNeeded(at url: URL) throws -> (url: URL, compileDurationMs: Double?) {
        if url.pathExtension == "mlmodelc" {
            return (url, nil)
        }

        let start = monotonicMilliseconds()
        let compiledURL = try MLModel.compileModel(at: url)
        return (compiledURL, monotonicMilliseconds() - start)
    }

    static func requiredPath(_ value: String?, label: String) throws -> String {
        let path = try requiredValue(value, label: label)
        guard FileManager.default.fileExists(atPath: path) else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool expected \(label) to exist at '\(path)', " +
                    "but no file or directory is present there.",
            )
        }

        return path
    }

    static func requiredValue(_ value: String?, label: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw UsageError.missingRequiredOption(label)
        }

        return value
    }

    static func requiredComputeUnits(_ value: String) throws -> MLComputeUnits {
        guard let computeUnits = coreMLComputeUnits(named: value) else {
            throw UsageError.invalidOptionValue("--compute-units", value)
        }

        return computeUnits
    }

    static func coreMLComputeUnits(named value: String) -> MLComputeUnits? {
        switch value {
            case "all":
                .all
            case "cpuOnly":
                .cpuOnly
            case "cpuAndGPU":
                .cpuAndGPU
            case "cpuAndNeuralEngine":
                .cpuAndNeuralEngine
            default:
                nil
        }
    }

    static func loadPaddedTalkerCodes(fixturePath: String, sampleID: String) throws -> CoreMLQwenPaddedCodes {
        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fixture = try decoder.decode(CoreMLQwenTalkerFixture.self, from: data)
        let matches = fixture.samples.filter { $0.id == sampleID }
        guard let sample = matches.first else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool could not find talker-code sample " +
                    "'\(sampleID)' in '\(fixturePath)'.",
            )
        }
        guard matches.count == 1 else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool found \(matches.count) talker-code " +
                    "samples named '\(sampleID)' in '\(fixturePath)', so the decoder input is ambiguous.",
            )
        }

        let codes = sample.encoded.audioCodes
        guard let quantizerCount = codes.first?.count, quantizerCount > 0 else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool found empty audio_codes for " +
                    "talker-code sample '\(sampleID)'.",
            )
        }
        guard codes.allSatisfy({ $0.count == quantizerCount }) else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool found ragged audio_codes for " +
                    "talker-code sample '\(sampleID)'.",
            )
        }

        let bucket = sample.bucketAssignment.assignedBucket
        guard codes.count <= bucket else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool cannot pad sample '\(sampleID)' because " +
                    "\(codes.count) code steps exceed bucket \(bucket).",
            )
        }

        var values = Array(
            repeating: sample.bucketAssignment.padValue,
            count: bucket * quantizerCount,
        )
        for step in 0..<codes.count {
            for quantizer in 0..<quantizerCount {
                values[(step * quantizerCount) + quantizer] = codes[step][quantizer]
            }
        }

        return CoreMLQwenPaddedCodes(
            sample: sample,
            inputShape: [1, bucket, quantizerCount],
            values: values,
            paddedStepCount: bucket - codes.count,
        )
    }

    static func makeAudioCodesMultiArray(_ paddedCodes: CoreMLQwenPaddedCodes) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: paddedCodes.inputShape.map(NSNumber.init(value:)),
            dataType: .int32,
        )
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: paddedCodes.values.count)
        for (index, value) in paddedCodes.values.enumerated() {
            pointer[index] = value
        }
        return array
    }

    static func predict(
        model: MLModel,
        provider: MLFeatureProvider,
    ) throws -> (durationMs: Double, audioValues: MLMultiArray) {
        let start = monotonicMilliseconds()
        let prediction = try model.prediction(from: provider)
        let durationMs = monotonicMilliseconds() - start
        guard let audioValues = prediction.featureValue(for: "audio_values")?.multiArrayValue else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool expected Core ML output feature " +
                    "'audio_values', but the decoder prediction did not return that MLMultiArray.",
            )
        }

        return (durationMs, audioValues)
    }

    static func requireOutputValues(_ output: MLMultiArray?) throws -> MLMultiArray {
        guard let output else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool completed zero measured decoder predictions, " +
                    "so no audio output was available to summarize.",
            )
        }

        return output
    }

    static func arrayValues(_ array: MLMultiArray) -> [Float] {
        (0..<array.count).map { Float(truncating: array[$0]) }
    }

    static func audioSummary(_ values: [Float]) -> CoreMLQwenDecoderReport.AudioSummary {
        guard !values.isEmpty else {
            return .init(sampleCount: 0, min: 0, max: 0, mean: 0, rms: 0)
        }

        var sum = 0.0
        var squareSum = 0.0
        var minimum = values[0]
        var maximum = values[0]
        for value in values {
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            sum += Double(value)
            squareSum += Double(value) * Double(value)
        }

        return .init(
            sampleCount: values.count,
            min: minimum,
            max: maximum,
            mean: sum / Double(values.count),
            rms: sqrt(squareSum / Double(values.count)),
        )
    }

    static func timingStats(_ values: [Double]) -> CoreMLQwenDecoderReport.TimingStats? {
        guard !values.isEmpty else {
            return nil
        }

        let ordered = values.sorted()
        let p95Index = min(ordered.count - 1, Int(Double(ordered.count) * 0.95))
        return .init(
            minMs: ordered[0],
            medianMs: ordered[ordered.count / 2],
            meanMs: values.reduce(0, +) / Double(values.count),
            p95Ms: ordered[p95Index],
            maxMs: ordered[ordered.count - 1],
        )
    }

    static func requiredTimingStats(_ values: [Double]) throws -> CoreMLQwenDecoderReport.TimingStats {
        guard let stats = timingStats(values) else {
            throw CoreMLQwenProbeError(
                message: "SpeakSwiftlyProbeTool requires at least one measured decoder " +
                    "prediction to produce timing stats.",
            )
        }

        return stats
    }

    static func writeCoreMLQwenDecoderReport(_ report: CoreMLQwenDecoderReport, output: String?) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let output {
            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: outputURL, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    static func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000
    }
}
