#if os(macOS)
import AppKit
import CoreServices
import Foundation

@MainActor
final class MacOSMediaVolumeDucker {
    typealias ScriptRunner = @MainActor @Sendable (_ source: String) throws -> Int
    typealias AutomationPermissionRequester = @MainActor @Sendable (_ app: MediaApp, _ shouldPrompt: Bool) -> AutomationPermissionState
    typealias RunningAppChecker = @MainActor @Sendable (_ app: MediaApp) -> Bool

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
        let duckedVolume: Int
    }

    static let supportedMediaApps: [MediaApp] = [
        MediaApp(name: "Spotify", bundleIdentifier: "com.spotify.client"),
        MediaApp(name: "Music", bundleIdentifier: "com.apple.Music"),
    ]
    static let duckRampWeights = [1, 2, 3, 2, 1]
    static let restoreRampWeights = [1, 2, 3, 4, 3, 2, 1]
    static let duckRampStepDelay: Duration = .milliseconds(35)
    static let restoreRampStepDelay: Duration = .milliseconds(70)
    static let volumeStabilitySampleDelay: Duration = .milliseconds(120)
    static let volumeStabilityAttemptLimit = 3
    static let restoreVerificationRetryDelay: Duration = .milliseconds(80)
    static let restoreVerificationRetryLimit = 2
    static let restoreUserAdjustmentTolerance = 1

    private let duckMediaVolume: SpeakSwiftly.DuckMediaVolume
    private let scriptRunner: ScriptRunner
    private let automationPermissionRequester: AutomationPermissionRequester
    private let runningAppChecker: RunningAppChecker
    private var duckedApps = [DuckedApp]()

    init(
        duckMediaVolume: SpeakSwiftly.DuckMediaVolume,
        scriptRunner: @escaping ScriptRunner = MacOSMediaVolumeDucker.runAppleScriptReturningInteger,
        automationPermissionRequester: @escaping AutomationPermissionRequester =
            MacOSMediaVolumeDucker.requestAutomationPermission,
        runningAppChecker: @escaping RunningAppChecker = MacOSMediaVolumeDucker.isRunning,
    ) {
        self.duckMediaVolume = duckMediaVolume
        self.scriptRunner = scriptRunner
        self.automationPermissionRequester = automationPermissionRequester
        self.runningAppChecker = runningAppChecker
        requestAutomationPermissionsIfNeeded(shouldPrompt: true)
    }

    static func getVolumeScript(for app: MediaApp) -> String {
        #"tell application id "\#(app.bundleIdentifier)" to get sound volume"#
    }

    static func setVolumeScript(for app: MediaApp, volume: Int) -> String {
        #"tell application id "\#(app.bundleIdentifier)" to set sound volume to \#(clampedVolume(volume))"#
    }

    static func isPlayingScript(for app: MediaApp) -> String {
        """
        tell application id "\(app.bundleIdentifier)"
            if player state is playing then
                return 1
            else
                return 0
            end if
        end tell
        """
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

    static func steppedVolumes(
        from startVolume: Int,
        to targetVolume: Int,
        weights: [Int],
    ) -> [Int] {
        let startVolume = clampedVolume(startVolume)
        let targetVolume = clampedVolume(targetVolume)
        guard startVolume != targetVolume else { return [] }

        let weights = weights.filter { $0 > 0 }
        guard !weights.isEmpty else { return [targetVolume] }

        let totalWeight = weights.reduce(0, +)
        let gap = targetVolume - startVolume
        var cumulativeWeight = 0
        var previousVolume = startVolume
        var volumes = [Int]()

        for weight in weights {
            cumulativeWeight += weight
            let progress = Double(cumulativeWeight) / Double(totalWeight)
            let volume = clampedVolume(
                startVolume + Int((Double(gap) * progress).rounded()),
            )
            guard volume != previousVolume else { continue }

            volumes.append(volume)
            previousVolume = volume
        }

        if volumes.last != targetVolume {
            volumes.append(targetVolume)
        }

        return volumes
    }

    static func shouldRestoreVolume(currentVolume: Int, duckedVolume: Int) -> Bool {
        abs(clampedVolume(currentVolume) - clampedVolume(duckedVolume)) <= restoreUserAdjustmentTolerance
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

    func duckRunningMediaApps() async {
        guard let reductionFraction = duckMediaVolume.reductionFraction else { return }
        guard duckedApps.isEmpty else { return }

        for app in Self.supportedMediaApps where runningAppChecker(app) {
            guard automationPermissionRequester(app, true) == .authorized else { continue }

            do {
                guard try scriptRunner(Self.isPlayingScript(for: app)) == 1 else { continue }
                guard let originalVolume = try await stableVolume(for: app) else { continue }

                let targetVolume = Self.reducedVolume(
                    from: originalVolume,
                    reductionFraction: reductionFraction,
                )
                guard targetVolume < originalVolume else { continue }

                try await applyVolumeRamp(
                    for: app,
                    from: originalVolume,
                    to: targetVolume,
                    weights: Self.duckRampWeights,
                    stepDelay: Self.duckRampStepDelay,
                )
                duckedApps.append(DuckedApp(app: app, originalVolume: originalVolume, duckedVolume: targetVolume))
            } catch {
                continue
            }
        }
    }

    func restoreDuckedMediaApps() async {
        guard !duckedApps.isEmpty else { return }

        let appsToRestore = duckedApps
        duckedApps.removeAll()

        for duckedApp in appsToRestore where runningAppChecker(duckedApp.app) {
            await restoreDuckedMediaApp(duckedApp)
        }
    }

    private func applyVolumeRamp(
        for app: MediaApp,
        from startVolume: Int,
        to targetVolume: Int,
        weights: [Int],
        stepDelay: Duration,
    ) async throws {
        for volume in Self.steppedVolumes(from: startVolume, to: targetVolume, weights: weights) {
            _ = try scriptRunner(Self.setVolumeScript(for: app, volume: volume))
            try? await playbackDelay(for: stepDelay)
        }
    }

    private func restoreDuckedMediaApp(_ duckedApp: DuckedApp) async {
        let targetVolume = Self.clampedVolume(duckedApp.originalVolume)

        do {
            guard let currentVolume = try await stableVolume(for: duckedApp.app) else { return }
            guard Self.shouldRestoreVolume(currentVolume: currentVolume, duckedVolume: duckedApp.duckedVolume) else {
                return
            }
        } catch {
            // Keep restore best-effort so playback teardown does not hide the request result.
        }

        for attempt in 0...Self.restoreVerificationRetryLimit {
            do {
                let currentVolume = try scriptRunner(Self.getVolumeScript(for: duckedApp.app))
                try await applyVolumeRamp(
                    for: duckedApp.app,
                    from: currentVolume,
                    to: targetVolume,
                    weights: Self.restoreRampWeights,
                    stepDelay: Self.restoreRampStepDelay,
                )

                let restoredVolume = try scriptRunner(Self.getVolumeScript(for: duckedApp.app))
                if Self.clampedVolume(restoredVolume) == targetVolume {
                    return
                }
            } catch {
                // Keep restore best-effort so playback teardown does not hide the request result.
            }

            if attempt < Self.restoreVerificationRetryLimit {
                try? await playbackDelay(for: Self.restoreVerificationRetryDelay)
            }
        }
    }

    private func stableVolume(for app: MediaApp) async throws -> Int? {
        var previousVolume = try scriptRunner(Self.getVolumeScript(for: app))

        for _ in 0..<Self.volumeStabilityAttemptLimit {
            try? await playbackDelay(for: Self.volumeStabilitySampleDelay)
            let currentVolume = try scriptRunner(Self.getVolumeScript(for: app))
            if Self.clampedVolume(currentVolume) == Self.clampedVolume(previousVolume) {
                return currentVolume
            }
            previousVolume = currentVolume
        }

        return nil
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
