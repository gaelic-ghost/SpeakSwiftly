import Foundation
@testable import SpeakSwiftly

// MARK: - WeakRuntimeBox

final class WeakRuntimeBox: @unchecked Sendable {
    weak var value: WorkerRuntime?
}

// MARK: - BackendLoadRecorder

actor BackendLoadRecorder {
    private var backends = [SpeakSwiftly.SpeechBackend]()

    func record(_ backend: SpeakSwiftly.SpeechBackend) {
        backends.append(backend)
    }

    func values() -> [SpeakSwiftly.SpeechBackend] {
        backends
    }
}

// MARK: - Runtime Control Surface Test Audio

func rawTestAudioData(for samples: [Float]) -> Data {
    let bytes = samples.map(\.bitPattern).flatMap { value in
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
    return Data(bytes)
}
