#if os(macOS)
import Foundation
@testable import SpeakSwiftly

func speakSwiftlyE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_E2E"] == "1"
}

func speakSwiftlyPlaybackTraceE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
}

func speakSwiftlyAudibleE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_AUDIBLE_E2E"] == "1"
}

func speakSwiftlyDeepTraceE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_DEEP_TRACE_E2E"] == "1"
}

func speakSwiftlyQwenBenchmarkE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_E2E"] == "1"
}

func speakSwiftlyQwenQuantBenchmarkE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_E2E"] == "1"
}

func speakSwiftlyQwenLongFormE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_LONGFORM_E2E"] == "1"
}

func speakSwiftlyQwenBackendE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BACKEND_E2E"] == "1"
}

func speakSwiftlyQwenBenchmarkIterations() -> Int {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS"] ?? ""
    return max(1, Int(rawValue) ?? 1)
}

func speakSwiftlyQwenQuantBenchmarkBackends() -> [SpeakSwiftly.SpeechBackend] {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_BACKENDS"] ?? ""
    let requestedBackends = rawValue
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !requestedBackends.isEmpty else {
        return SpeakSwiftly.SpeechBackend.qwenFamilyBackends
    }

    var backends = [SpeakSwiftly.SpeechBackend]()
    var invalidBackends = [String]()
    for requestedBackend in requestedBackends {
        if let backend = SpeakSwiftly.SpeechBackend.normalized(rawValue: requestedBackend) {
            backends.append(backend)
        } else {
            invalidBackends.append(requestedBackend)
        }
    }

    precondition(
        invalidBackends.isEmpty,
        """
        SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_BACKENDS contains unsupported backend value(s): \(invalidBackends.joined(separator: ", ")). \
        Use one or more SpeechBackend.qwenFamilyBackends raw values separated by commas.
        """,
    )
    return backends
}

func speakSwiftlyQwenQuantBenchmarkDeviceLabel() -> String? {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_DEVICE_LABEL"] ?? ""
    let label = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return label.isEmpty ? nil : label
}

#endif
