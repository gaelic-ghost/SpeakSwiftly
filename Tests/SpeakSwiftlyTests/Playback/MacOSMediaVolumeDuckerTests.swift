#if os(macOS)
import CoreServices
@testable import SpeakSwiftly
import Testing

@MainActor
private final class MediaVolumeScriptSpy {
    var setCalls = [(appName: String, volume: Int)]()
    var failedFinalRestoreWritesRemaining = 0
    var finalRestoreTargetWriteCount = 0

    private var volumes: [String: Int]

    init(volumes: [String: Int]) {
        self.volumes = volumes
    }

    func volume(for appName: String) -> Int? {
        volumes[appName]
    }

    func run(_ source: String) throws -> Int {
        let appName = if source.contains(#""Spotify""#) {
            "Spotify"
        } else {
            "Music"
        }

        if source.contains("get sound volume") {
            return volumes[appName] ?? 100
        }

        let volume = Int(source.split(separator: " ").last ?? "") ?? 0
        setCalls.append((appName: appName, volume: volume))
        if volume == 100 {
            finalRestoreTargetWriteCount += 1
        }
        if volume == 100, failedFinalRestoreWritesRemaining > 0 {
            failedFinalRestoreWritesRemaining -= 1
            volumes[appName] = 96
        } else {
            volumes[appName] = volume
        }
        return volumes[appName] ?? volume
    }

    func resetSetCalls() {
        setCalls.removeAll()
    }
}

@MainActor
@Test func `macOS media volume ducker writes expected AppleScript commands`() {
    let spotify = MacOSMediaVolumeDucker.MediaApp(
        name: "Spotify",
        bundleIdentifier: "com.spotify.client",
    )

    #expect(MacOSMediaVolumeDucker.getVolumeScript(for: spotify) == #"tell application "Spotify" to get sound volume"#)
    #expect(MacOSMediaVolumeDucker.setVolumeScript(for: spotify, volume: 35) == #"tell application "Spotify" to set sound volume to 35"#)
}

@MainActor
@Test func `macOS media volume ducker clamps volume before scripting`() {
    let music = MacOSMediaVolumeDucker.MediaApp(
        name: "Music",
        bundleIdentifier: "com.apple.Music",
    )

    #expect(MacOSMediaVolumeDucker.setVolumeScript(for: music, volume: -12) == #"tell application "Music" to set sound volume to 0"#)
    #expect(MacOSMediaVolumeDucker.setVolumeScript(for: music, volume: 123) == #"tell application "Music" to set sound volume to 100"#)
}

@MainActor
@Test func `macOS media volume ducker reduces current volume by fraction`() {
    #expect(MacOSMediaVolumeDucker.reducedVolume(from: 100, reductionFraction: 0.20) == 80)
    #expect(MacOSMediaVolumeDucker.reducedVolume(from: 80, reductionFraction: 0.35) == 52)
    #expect(MacOSMediaVolumeDucker.reducedVolume(from: 40, reductionFraction: 0.75) == 10)
}

@MainActor
@Test func `macOS media volume ducker builds shaped duck and restore ramps`() {
    #expect(
        MacOSMediaVolumeDucker.steppedVolumes(
            from: 100,
            to: 80,
            weights: MacOSMediaVolumeDucker.duckRampWeights,
        ) == [98, 93, 87, 82, 80],
    )
    #expect(
        MacOSMediaVolumeDucker.steppedVolumes(
            from: 80,
            to: 100,
            weights: MacOSMediaVolumeDucker.restoreRampWeights,
        ) == [81, 84, 88, 93, 96, 99, 100],
    )
}

@MainActor
@Test func `macOS media volume ducker lowers running media apps with shaped ramp`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()

    #expect(spy.setCalls.map(\.volume) == [98, 93, 87, 82, 80])
    #expect(spy.volume(for: "Spotify") == 80)
}

@MainActor
@Test func `macOS media volume ducker verifies restore and retries when final volume does not stick`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()
    spy.resetSetCalls()
    spy.failedFinalRestoreWritesRemaining = 1

    await ducker.restoreDuckedMediaApps()

    #expect(spy.volume(for: "Spotify") == 100)
    #expect(spy.finalRestoreTargetWriteCount == 2)
}

@MainActor
@Test func `macOS media volume ducker maps automation permission statuses`() {
    #expect(MacOSMediaVolumeDucker.permissionState(for: noErr) == .authorized)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventNotPermitted)) == .denied)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(procNotFound)) == .unavailable)
}
#endif
