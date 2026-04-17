import Foundation

// MARK: - PlaybackEnvironmentCoordinator

@MainActor
protocol PlaybackEnvironmentCoordinator: AnyObject, Sendable {
    var currentOutputDeviceDescription: String? { get }

    func installObservers(
        onSystemSleepStateChange: @escaping @MainActor (Bool) -> Void,
        onScreenSleepStateChange: @escaping @MainActor (Bool) -> Void,
        onSessionActivityChange: @escaping @MainActor (Bool) -> Void,
        onOutputDeviceChange: @escaping @MainActor (String?) -> Void,
        onInterruptionStateChange: @escaping @MainActor (_ isInterrupted: Bool, _ shouldResume: Bool?) -> Void,
    )

    func prepareForPlaybackStart() async throws
    func finishPlayback()
    func invalidate()
}

// MARK: - Playback Environment Factory

@MainActor
func makeDefaultPlaybackEnvironmentCoordinator() -> PlaybackEnvironmentCoordinator {
    #if os(macOS)
        MacOSPlaybackEnvironmentCoordinator()
    #elseif os(iOS)
        IOSPlaybackEnvironmentCoordinator()
    #else
        fatalError("SpeakSwiftly does not support local playback environment coordination on this platform.")
    #endif
}
