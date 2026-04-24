import Foundation
@testable import SpeakSwiftly
import Testing

final class WeakRuntimeBox: @unchecked Sendable {
    weak var value: WorkerRuntime?
}

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

func rawTestAudioSamples(from data: Data) -> [Float] {
    stride(from: 0, to: data.count, by: MemoryLayout<Float>.size).map { offset in
        data[offset..<offset + MemoryLayout<Float>.size].withUnsafeBytes { bytes in
            Float(bitPattern: UInt32(littleEndian: bytes.load(as: UInt32.self)))
        }
    }
}

func expectAudioSamples(
    _ actual: [Float],
    approximatelyEqualTo expected: [Float],
    tolerance: Float = 0.000_001,
) {
    #expect(actual.count == expected.count)
    for (actualSample, expectedSample) in zip(actual, expected) {
        #expect(abs(actualSample - expectedSample) <= tolerance)
    }
}
