@preconcurrency import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioPlaybackConfiguration

enum AudioPlaybackConfiguration {
    static let minimumDrainTimeout: Duration = .seconds(5)
    static let drainTimeoutPaddingMS = 3000
    static let drainProgressCheckIntervalMS = 500
    static let drainProgressStallTimeoutMS = 8000
    static let environmentInstabilityWindowMS = 8000
    static let recoveryStabilizationDelayMS = 900
    static let recoveryMaximumAttempts = 3
    static let lowQueueThresholdMS = 100
    static let channels: AVAudioChannelCount = 1
    static let interJobBoopDurationMS = 90
    static let interJobBoopFrequencyHz = 1176.0
    static let interJobBoopAmplitude: Float = 0.14
    static let interJobBoopFadeMS = 10
    static let interJobBoopTimeout: Duration = .seconds(2)

    static func drainTimeout(forQueuedAudioMS queuedAudioMS: Int) -> Duration {
        let paddedQueuedAudioMS = queuedAudioMS + drainTimeoutPaddingMS
        return max(minimumDrainTimeout, .milliseconds(paddedQueuedAudioMS))
    }
}

// MARK: - Playback Device Inspection

func currentDefaultAudioPlaybackDeviceDescription() -> String? {
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
