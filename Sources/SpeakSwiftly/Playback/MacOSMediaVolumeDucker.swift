#if os(macOS)
import AppKit
import CoreServices
import Foundation

@MainActor
final class MacOSMediaVolumeDucker {
    typealias ScriptRunner = @MainActor @Sendable (_ source: String) throws -> Int
    typealias AutomationPermissionRequester = @MainActor @Sendable (_ app: MediaApp, _ shouldPrompt: Bool) -> AutomationPermissionState

    struct MediaApp: Equatable {
        let name: String
        let bundleIdentifier: String
    }

    enum AutomationPermissionState: Equatable {
        case authorized
        case notDetermined
        case denied
        case unavailable
    }

    private struct DuckedApp: Equatable {
        let app: MediaApp
        let originalVolume: Int
    }

    static let supportedMediaApps: [MediaApp] = [
        MediaApp(name: "Spotify", bundleIdentifier: "com.spotify.client"),
        MediaApp(name: "Music", bundleIdentifier: "com.apple.Music"),
    ]

    private let duckMediaVolume: SpeakSwiftly.DuckMediaVolume
    private let scriptRunner: ScriptRunner
    private let automationPermissionRequester: AutomationPermissionRequester
    private var duckedApps = [DuckedApp]()

    init(
        duckMediaVolume: SpeakSwiftly.DuckMediaVolume,
        scriptRunner: @escaping ScriptRunner = MacOSMediaVolumeDucker.runAppleScriptReturningInteger,
        automationPermissionRequester: @escaping AutomationPermissionRequester =
            MacOSMediaVolumeDucker.requestAutomationPermission,
    ) {
        self.duckMediaVolume = duckMediaVolume
        self.scriptRunner = scriptRunner
        self.automationPermissionRequester = automationPermissionRequester
        requestAutomationPermissionsIfNeeded(shouldPrompt: true)
    }

    static func getVolumeScript(for app: MediaApp) -> String {
        #"tell application "\#(app.name)" to get sound volume"#
    }

    static func setVolumeScript(for app: MediaApp, volume: Int) -> String {
        #"tell application "\#(app.name)" to set sound volume to \#(clampedVolume(volume))"#
    }

    static func clampedVolume(_ volume: Int) -> Int {
        min(max(volume, 0), 100)
    }

    static func reducedVolume(
        from volume: Int,
        reductionFraction: Double,
    ) -> Int {
        let clampedOriginalVolume = clampedVolume(volume)
        let clampedReductionFraction = min(max(reductionFraction, 0), 1)
        return clampedVolume(
            Int((Double(clampedOriginalVolume) * (1 - clampedReductionFraction)).rounded()),
        )
    }

    static func permissionState(for status: OSStatus) -> AutomationPermissionState {
        switch status {
            case noErr:
                .authorized
            case OSStatus(errAEEventWouldRequireUserConsent):
                .notDetermined
            case OSStatus(errAEEventNotPermitted):
                .denied
            default:
                .unavailable
        }
    }

    private static func isRunning(_ app: MediaApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    private static func requestAutomationPermission(
        for app: MediaApp,
        shouldPrompt: Bool,
    ) -> AutomationPermissionState {
        guard isRunning(app) else { return .unavailable }

        let descriptor = NSAppleEventDescriptor(bundleIdentifier: app.bundleIdentifier)
        guard let target = descriptor.aeDesc else { return .unavailable }

        let status = AEDeterminePermissionToAutomateTarget(
            target,
            typeWildCard,
            typeWildCard,
            shouldPrompt,
        )
        return permissionState(for: status)
    }

    private static func runAppleScriptReturningInteger(_ source: String) throws -> Int {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "SpeakSwiftly could not prepare an AppleScript command for macOS media volume ducking.",
            )
        }

        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "The AppleScript command returned an unknown error."
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "SpeakSwiftly could not run an AppleScript command for macOS media volume ducking. \(message)",
            )
        }

        return Int(descriptor.int32Value)
    }

    func duckRunningMediaApps() {
        guard let reductionFraction = duckMediaVolume.reductionFraction else { return }
        guard duckedApps.isEmpty else { return }

        for app in Self.supportedMediaApps where Self.isRunning(app) {
            guard automationPermissionRequester(app, true) == .authorized else { continue }

            do {
                let originalVolume = try scriptRunner(Self.getVolumeScript(for: app))
                let targetVolume = Self.reducedVolume(
                    from: originalVolume,
                    reductionFraction: reductionFraction,
                )
                guard targetVolume < originalVolume else { continue }

                _ = try scriptRunner(Self.setVolumeScript(for: app, volume: targetVolume))
                duckedApps.append(DuckedApp(app: app, originalVolume: originalVolume))
            } catch {
                continue
            }
        }
    }

    func restoreDuckedMediaApps() {
        guard !duckedApps.isEmpty else { return }

        let appsToRestore = duckedApps
        duckedApps.removeAll()

        for duckedApp in appsToRestore where Self.isRunning(duckedApp.app) {
            do {
                _ = try scriptRunner(Self.setVolumeScript(for: duckedApp.app, volume: duckedApp.originalVolume))
            } catch {
                continue
            }
        }
    }

    private func requestAutomationPermissionsIfNeeded(shouldPrompt: Bool) {
        guard duckMediaVolume.requiresMediaAutomation else { return }

        for app in Self.supportedMediaApps {
            _ = automationPermissionRequester(app, shouldPrompt)
        }
    }
}

private extension SpeakSwiftly.DuckMediaVolume {
    var reductionFraction: Double? {
        switch self {
            case .off:
                nil
            case .aLittle:
                0.20
            case .default:
                0.35
            case .aLot:
                0.75
        }
    }
}
#endif
