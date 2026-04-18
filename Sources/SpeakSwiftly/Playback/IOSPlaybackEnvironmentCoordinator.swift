#if os(iOS)
@preconcurrency import AVFoundation
import Foundation

// MARK: - IOSPlaybackEnvironmentCoordinator

@MainActor
final class IOSPlaybackEnvironmentCoordinator: PlaybackEnvironmentCoordinator {
    private let audioSession = AVAudioSession.sharedInstance()
    private var observerTasks = [Task<Void, Never>]()
    private var observersInstalled = false

    var currentOutputDeviceDescription: String? {
        Self.currentOutputRouteDescription(audioSession.currentRoute)
    }

    private static func parseInterruption(_ notification: Notification) -> (Bool, Bool?) {
        guard
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return (true, nil)
        }

        switch type {
            case .began:
                return (true, nil)
            case .ended:
                guard let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return (false, nil)
                }

                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                return (false, options.contains(.shouldResume))
            @unknown default:
                return (false, nil)
        }
    }

    private static func currentOutputRouteDescription(_ route: AVAudioSessionRouteDescription) -> String? {
        let outputs = route.outputs.map { output in
            "\(output.portName) [\(output.portType.rawValue)]"
        }
        guard !outputs.isEmpty else { return nil }

        return outputs.joined(separator: ", ")
    }

    func installObservers(
        onSystemSleepStateChange: @escaping @MainActor (Bool) -> Void,
        onScreenSleepStateChange: @escaping @MainActor (Bool) -> Void,
        onSessionActivityChange: @escaping @MainActor (Bool) -> Void,
        onOutputDeviceChange: @escaping @MainActor (String?) -> Void,
        onInterruptionStateChange: @escaping @MainActor (_ isInterrupted: Bool, _ shouldResume: Bool?) -> Void,
    ) {
        guard !observersInstalled else { return }

        observersInstalled = true

        observerTasks.append(
            Task { @MainActor [audioSession] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVAudioSession.routeChangeNotification,
                    object: audioSession,
                ) {
                    onOutputDeviceChange(Self.currentOutputRouteDescription(audioSession.currentRoute))
                }
            },
        )

        observerTasks.append(
            Task { @MainActor [audioSession] in
                for await notification in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification,
                    object: audioSession,
                ) {
                    let (isInterrupted, shouldResume) = Self.parseInterruption(notification)
                    onInterruptionStateChange(isInterrupted, shouldResume)
                    onSessionActivityChange(!isInterrupted)
                }
            },
        )
    }

    func prepareForPlaybackStart() async throws {
        do {
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
        } catch {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "SpeakSwiftly could not activate the iOS audio session before starting local playback. \(error.localizedDescription)",
            )
        }
    }

    func finishPlayback() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Keep teardown best-effort so playback shutdown does not mask the real request result.
        }
    }

    func invalidate() {
        for observerTask in observerTasks {
            observerTask.cancel()
        }
        observerTasks.removeAll()
        observersInstalled = false
        finishPlayback()
    }
}
#endif
