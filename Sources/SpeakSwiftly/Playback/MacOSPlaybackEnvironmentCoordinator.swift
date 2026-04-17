#if os(macOS)
@preconcurrency import AppKit
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

// MARK: - MacOSPlaybackEnvironmentCoordinator

@MainActor
final class MacOSPlaybackEnvironmentCoordinator: PlaybackEnvironmentCoordinator {
    private var workspaceObservers = [NSObjectProtocol]()
    private var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    )
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var routingArbitration = AVAudioRoutingArbiter.shared
    private var observersInstalled = false

    var currentOutputDeviceDescription: String? {
        Self.currentDefaultAudioPlaybackDeviceDescription()
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

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onSystemSleepStateChange(true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onSystemSleepStateChange(false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onScreenSleepStateChange(true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onScreenSleepStateChange(false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onSessionActivityChange(false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: nil,
            ) { _ in
                Task { @MainActor in
                    onSessionActivityChange(true)
                }
            },
        )

        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                onOutputDeviceChange(Self.currentDefaultAudioPlaybackDeviceDescription())
            }
        }
        defaultOutputDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputDeviceAddress,
            DispatchQueue.main,
            listener,
        )
    }

    func prepareForPlaybackStart() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routingArbitration.begin(category: .playback) { _, error in
                if let error {
                    continuation.resume(
                        throwing: WorkerError(
                            code: .audioPlaybackFailed,
                            message: "SpeakSwiftly could not begin macOS audio routing arbitration before starting local playback. \(error.localizedDescription)",
                        ),
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func finishPlayback() {
        routingArbitration.leave()
    }

    func invalidate() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if let defaultOutputDeviceListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputDeviceAddress,
                DispatchQueue.main,
                defaultOutputDeviceListener,
            )
            self.defaultOutputDeviceListener = nil
        }

        routingArbitration.leave()
        observersInstalled = false
    }

    private static func currentDefaultAudioPlaybackDeviceDescription() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &dataSize,
            &deviceID,
        )

        guard deviceStatus == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.stride)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let nameStatus = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                UnsafeMutableRawPointer(pointer),
            )
        }

        if nameStatus == noErr {
            let name = "\(deviceName)"
            if !name.isEmpty {
                return "\(name) [\(deviceID)]"
            }
        }

        return "AudioObjectID \(deviceID)"
    }
}
#endif
