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
    private var playingApps: Set<String>
    private var volumeReadSequences: [String: [Int]]

    init(volumes: [String: Int], playingApps: Set<String>? = nil) {
        self.volumes = volumes
        self.playingApps = playingApps ?? Set(volumes.keys)
        volumeReadSequences = [:]
    }

    func volume(for appName: String) -> Int? {
        volumes[appName]
    }

    func setVolume(_ volume: Int, for appName: String) {
        volumes[appName] = volume
    }

    func setVolumeReadSequence(_ sequence: [Int], for appName: String) {
        volumeReadSequences[appName] = sequence
    }

    func run(_ source: String) throws -> Int {
        let appName = if source.contains(#""com.spotify.client""#) {
            "Spotify"
        } else {
            "Music"
        }

        if source.contains("player state") {
            return playingApps.contains(appName) ? 1 : 0
        }

        if source.contains("get sound volume") {
            if var sequence = volumeReadSequences[appName], !sequence.isEmpty {
                let volume = sequence.removeFirst()
                volumeReadSequences[appName] = sequence
                volumes[appName] = volume
                return volume
            }
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

    #expect(
        MacOSMediaVolumeDucker.getVolumeScript(for: spotify)
            == #"tell application id "com.spotify.client" to get sound volume"#,
    )
    #expect(
        MacOSMediaVolumeDucker.setVolumeScript(for: spotify, volume: 35)
            == #"tell application id "com.spotify.client" to set sound volume to 35"#,
    )
    #expect(
        MacOSMediaVolumeDucker.isPlayingScript(for: spotify).contains(
            #"tell application id "com.spotify.client""#,
        ),
    )
    #expect(MacOSMediaVolumeDucker.isPlayingScript(for: spotify).contains("player state is playing"))
}

@MainActor
@Test func `macOS media volume ducker clamps volume before scripting`() {
    let music = MacOSMediaVolumeDucker.MediaApp(
        name: "Music",
        bundleIdentifier: "com.apple.Music",
    )

    #expect(
        MacOSMediaVolumeDucker.setVolumeScript(for: music, volume: -12)
            == #"tell application id "com.apple.Music" to set sound volume to 0"#,
    )
    #expect(
        MacOSMediaVolumeDucker.setVolumeScript(for: music, volume: 123)
            == #"tell application id "com.apple.Music" to set sound volume to 100"#,
    )
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
@Test func `macOS media volume ducker only lowers apps that are currently playing`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100, "Music": 80], playingApps: ["Spotify"])
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { _ in true },
    )

    await ducker.duckRunningMediaApps()

    #expect(spy.setCalls.map(\.appName) == ["Spotify", "Spotify", "Spotify", "Spotify", "Spotify"])
    #expect(spy.volume(for: "Spotify") == 80)
    #expect(spy.volume(for: "Music") == 80)
}

@MainActor
@Test func `macOS media volume ducker waits for stable volume before ducking`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    spy.setVolumeReadSequence([100, 95, 95], for: "Spotify")
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()

    #expect(spy.setCalls.map(\.volume) == [93, 89, 82, 78, 76])
    #expect(spy.volume(for: "Spotify") == 76)
}

@MainActor
@Test func `macOS media volume ducker skips ducking while volume keeps changing`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    spy.setVolumeReadSequence([100, 95, 90, 85], for: "Spotify")
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()

    #expect(spy.setCalls.isEmpty)
    #expect(spy.volume(for: "Spotify") == 85)
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
@Test func `macOS media volume ducker skips restore while volume keeps changing`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()
    spy.resetSetCalls()
    spy.setVolumeReadSequence([80, 70, 60, 50], for: "Spotify")

    await ducker.restoreDuckedMediaApps()

    #expect(spy.setCalls.isEmpty)
    #expect(spy.volume(for: "Spotify") == 50)
}

@MainActor
@Test func `macOS media volume ducker leaves user adjusted volume alone during restore`() async {
    let spy = MediaVolumeScriptSpy(volumes: ["Spotify": 100])
    let ducker = MacOSMediaVolumeDucker(
        duckMediaVolume: .aLittle,
        scriptRunner: { try spy.run($0) },
        automationPermissionRequester: { _, _ in .authorized },
        runningAppChecker: { $0.name == "Spotify" },
    )

    await ducker.duckRunningMediaApps()
    spy.resetSetCalls()
    spy.setVolume(65, for: "Spotify")

    await ducker.restoreDuckedMediaApps()

    #expect(spy.setCalls.isEmpty)
    #expect(spy.volume(for: "Spotify") == 65)
}

@MainActor
@Test func `macOS media volume ducker maps automation permission statuses`() {
    #expect(MacOSMediaVolumeDucker.permissionState(for: noErr) == .authorized)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventNotPermitted)) == .denied)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(procNotFound)) == .unavailable)
}
#endif
