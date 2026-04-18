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
    ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_E2E"] == "1"
}

func speakSwiftlyQwenBenchmarkIterations() -> Int {
    let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS"] ?? ""
    return max(1, Int(rawValue) ?? 1)
}
#endif
