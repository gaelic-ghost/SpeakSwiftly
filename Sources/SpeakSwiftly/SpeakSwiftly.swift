import Foundation

// MARK: - Public Runtime

public enum SpeakSwiftly {
    public static func makeLiveRuntime() async -> WorkerRuntime {
        await WorkerRuntime.live()
    }
}
