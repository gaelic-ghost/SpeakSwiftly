@preconcurrency import AVFoundation
import Darwin
import Foundation
@preconcurrency import MLX
import MLXAudioCore

// MARK: - WorkerDependencies

struct WorkerDependencies: @unchecked Sendable {
    private enum Environment {
        static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
        static let playbackTrace = "SPEAKSWIFTLY_PLAYBACK_TRACE"
    }

    let fileManager: FileManager
    let loadResidentModels: @Sendable (_ backend: SpeakSwiftly.SpeechBackend) async throws -> ResidentSpeechModels
    let loadProfileModel: @Sendable () async throws -> AnySpeechModel
    let loadCloneTranscriptionModel: @Sendable () async throws -> AnyCloneTranscriptionModel
    let makePlaybackController: @MainActor @Sendable () -> AnyPlaybackController
    let writeWAV: @Sendable (_ samples: [Float], _ sampleRate: Int, _ url: URL) throws -> Void
    let loadAudioSamples: @Sendable (_ url: URL, _ sampleRate: Int) throws -> MLXArray?
    let loadAudioFloats: @Sendable (_ url: URL, _ sampleRate: Int) throws -> [Float]
    let writeStdout: @Sendable (Data) throws -> Void
    let writeStderr: @Sendable (String) -> Void
    let now: @Sendable () -> Date
    let readRuntimeMemory: @Sendable () -> RuntimeMemorySnapshot?

    static func live(fileManager: FileManager = .default) -> WorkerDependencies {
        let environment = ProcessInfo.processInfo.environment

        return WorkerDependencies(
            fileManager: fileManager,
            loadResidentModels: { backend in try await ModelFactory.loadResidentModels(for: backend) },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            loadCloneTranscriptionModel: { try await ModelFactory.loadCloneTranscriptionModel() },
            makePlaybackController: {
                if environment[Environment.silentPlayback] == "1" {
                    return .silent(traceEnabled: environment[Environment.playbackTrace] == "1")
                }

                return AnyPlaybackController(
                    AudioPlaybackDriver(traceEnabled: environment[Environment.playbackTrace] == "1"),
                )
            },
            writeWAV: { samples, sampleRate, url in
                try AudioUtils.writeWavFile(
                    samples: samples,
                    sampleRate: Double(sampleRate),
                    fileURL: url,
                )
            },
            loadAudioSamples: { url, sampleRate in
                let (_, audio) = try MLXAudioCore.loadAudioArray(from: url, sampleRate: sampleRate)
                return audio
            },
            loadAudioFloats: loadFloatAudioSamples,
            writeStdout: { data in
                try FileHandle.standardOutput.write(contentsOf: data)
            },
            writeStderr: { message in
                do {
                    try FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
                } catch {
                    fputs(message + "\n", stderr)
                }
            },
            now: Date.init,
            readRuntimeMemory: currentRuntimeMemorySnapshot,
        )
    }
}

private func loadFloatAudioSamples(from url: URL, sampleRate: Int) throws -> [Float] {
    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.processingFormat
    let sourceSampleRate = Int(format.sampleRate.rounded())
    let frameCapacity = max(AVAudioFrameCount(audioFile.length), 1)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not allocate an audio buffer while reading '\(url.path)'.",
        )
    }

    try audioFile.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not access floating-point samples while decoding '\(url.path)'. The file may use an unsupported audio format.",
        )
    }

    let channelCount = Int(format.channelCount)
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return [] }

    var mono = [Float](repeating: 0, count: frameLength)

    if channelCount == 1 {
        mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    } else {
        let divisor = Float(channelCount)
        for frameIndex in 0..<frameLength {
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                sum += channelData[channelIndex][frameIndex]
            }
            mono[frameIndex] = sum / divisor
        }
    }

    guard sampleRate > 0 else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly was asked to decode '\(url.path)' with invalid target sample rate \(sampleRate).",
        )
    }

    if sourceSampleRate == sampleRate {
        return mono
    }

    do {
        return try resampleAudio(mono, from: sourceSampleRate, to: sampleRate)
    } catch {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not resample '\(url.path)' from \(sourceSampleRate) Hz to \(sampleRate) Hz. \(error.localizedDescription)",
        )
    }
}

private func currentRuntimeMemorySnapshot() -> RuntimeMemorySnapshot? {
    let snapshot = Memory.snapshot()

#if os(macOS)
    var usage = rusage_info_current()
    let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
            proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
        }
    }

    let processResidentBytes = usageResult == 0 ? Int(usage.ri_resident_size) : nil
    let processPhysFootprintBytes = usageResult == 0 ? Int(usage.ri_phys_footprint) : nil
    let processUserCPUTimeNS = usageResult == 0 ? Int(usage.ri_user_time) : nil
    let processSystemCPUTimeNS = usageResult == 0 ? Int(usage.ri_system_time) : nil
#else
    let processResidentBytes: Int? = nil
    let processPhysFootprintBytes: Int? = nil
    let processUserCPUTimeNS: Int? = nil
    let processSystemCPUTimeNS: Int? = nil
#endif

    return RuntimeMemorySnapshot(
        processResidentBytes: processResidentBytes,
        processPhysFootprintBytes: processPhysFootprintBytes,
        processUserCPUTimeNS: processUserCPUTimeNS,
        processSystemCPUTimeNS: processSystemCPUTimeNS,
        mlxActiveMemoryBytes: snapshot.activeMemory,
        mlxCacheMemoryBytes: snapshot.cacheMemory,
        mlxPeakMemoryBytes: snapshot.peakMemory,
        mlxCacheLimitBytes: Memory.cacheLimit,
        mlxMemoryLimitBytes: Memory.memoryLimit,
    )
}
