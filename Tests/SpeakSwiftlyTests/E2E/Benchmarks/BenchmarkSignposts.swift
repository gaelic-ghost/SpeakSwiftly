#if os(macOS)
import Foundation
import os
@testable import SpeakSwiftly

struct BenchmarkSignpostRecorder {
    private static let subsystem = "com.gaelic-ghost.SpeakSwiftly.benchmarks"

    private let signposter: OSSignposter

    init(
        backend: SpeakSwiftly.SpeechBackend,
        playbackMode: BenchmarkPlaybackMode,
    ) {
        signposter = OSSignposter(
            subsystem: Self.subsystem,
            category: "benchmark.\(backend.rawValue).\(playbackMode.rawValue)",
        )
    }

    func beginSample() -> BenchmarkSignpostInterval {
        beginInterval("Benchmark Sample")
    }

    func beginResidentPreload() -> BenchmarkSignpostInterval {
        beginInterval("Resident Preload")
    }

    func beginRequest() -> BenchmarkSignpostInterval {
        beginInterval("Benchmark Request")
    }

    func emitQueued(id: OSSignpostID) {
        signposter.emitEvent("Request Queued", id: id)
    }

    func emitAcknowledged(id: OSSignpostID) {
        signposter.emitEvent("Request Acknowledged", id: id)
    }

    func emitStarted(id: OSSignpostID) {
        signposter.emitEvent("Request Started", id: id)
    }

    func emitBufferingAudio(id: OSSignpostID) {
        signposter.emitEvent("Buffering Audio", id: id)
    }

    func emitPrerollReady(id: OSSignpostID) {
        signposter.emitEvent("Preroll Ready", id: id)
    }

    func emitPlaybackFinished(id: OSSignpostID) {
        signposter.emitEvent("Playback Finished", id: id)
    }

    func emitCompleted(id: OSSignpostID) {
        signposter.emitEvent("Request Completed", id: id)
    }

    func emitFirstToken(id: OSSignpostID) {
        signposter.emitEvent("First Token", id: id)
    }

    func emitGenerationInfo(id: OSSignpostID) {
        signposter.emitEvent("Generation Info", id: id)
    }

    func emitFirstAudioChunk(id: OSSignpostID) {
        signposter.emitEvent("First Audio Chunk", id: id)
    }

    private func beginInterval(_ name: StaticString) -> BenchmarkSignpostInterval {
        let id = signposter.makeSignpostID()
        return BenchmarkSignpostInterval(
            signposter: signposter,
            id: id,
            name: name,
            state: signposter.beginInterval(name, id: id),
        )
    }
}

struct BenchmarkSignpostInterval {
    let signposter: OSSignposter
    let id: OSSignpostID
    let name: StaticString
    let state: OSSignpostIntervalState

    func end() {
        signposter.endInterval(name, state)
    }
}
#endif
