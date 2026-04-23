#if os(macOS)
import Foundation

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
    let environment = ProcessInfo.processInfo.environment
    return environment["SPEAKSWIFTLY_QWEN_BENCHMARK_E2E"] == "1"
        || environment["SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E"] == "1"
}

func speakSwiftlyQwenLongFormE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_LONGFORM_E2E"] == "1"
}

func speakSwiftlyQwenBenchmarkIterations() -> Int {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS"] ?? ""
    if let parsed = Int(rawValue) {
        return max(1, parsed)
    }

    return speakSwiftlyBackendBenchmarkIterations()
}

func speakSwiftlyBackendBenchmarkE2ETestsEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E"] == "1"
}

func speakSwiftlyBackendBenchmarkIterations() -> Int {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS"] ?? ""
    return max(1, Int(rawValue) ?? 1)
}

func speakSwiftlyBackendBenchmarkAudibleEnabled() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["SPEAKSWIFTLY_BACKEND_BENCHMARK_AUDIBLE"] == "1"
        || environment["SPEAKSWIFTLY_AUDIBLE_E2E"] == "1"
}
#endif
