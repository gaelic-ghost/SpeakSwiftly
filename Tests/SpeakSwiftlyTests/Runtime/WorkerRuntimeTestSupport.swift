import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - LoadedBackendRecorder

actor LoadedBackendRecorder {
    private(set) var backends = [SpeakSwiftly.SpeechBackend]()

    func record(_ backend: SpeakSwiftly.SpeechBackend) {
        backends.append(backend)
    }
}

func makeSpeechBackendResolutionDependencies(
    fileManager: FileManager = .default,
    stderrMessages: @escaping @Sendable (String) -> Void = { _ in },
) -> WorkerDependencies {
    WorkerDependencies(
        fileManager: fileManager,
        loadResidentModels: { backend in makeResidentModels(for: backend) },
        loadProfileModel: { makeProfileModel() },
        loadCloneTranscriptionModel: { makeCloneTranscriptionModel() },
        makePlaybackController: { AnyPlaybackController.silent() },
        writeWAV: { _, _, _ in },
        loadAudioSamples: { _, _ in nil },
        loadAudioFloats: { _, _ in [] },
        writeStdout: { _ in },
        writeStderr: stderrMessages,
        now: Date.init,
        readRuntimeMemory: { nil },
    )
}
