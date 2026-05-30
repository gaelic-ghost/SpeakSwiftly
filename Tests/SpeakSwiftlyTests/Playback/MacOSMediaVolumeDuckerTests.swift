#if os(macOS)
import CoreServices
@testable import SpeakSwiftly
import Testing

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
@Test func `macOS media volume ducker maps automation permission statuses`() {
    #expect(MacOSMediaVolumeDucker.permissionState(for: noErr) == .authorized)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(errAEEventNotPermitted)) == .denied)
    #expect(MacOSMediaVolumeDucker.permissionState(for: OSStatus(procNotFound)) == .unavailable)
}
#endif
