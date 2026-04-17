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
    )

    func prepareForPlaybackStart() async throws
    func finishPlayback()
    func invalidate()
}
