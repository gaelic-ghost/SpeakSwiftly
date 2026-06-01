import Foundation

public enum GeneratedAudioFileFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case wav
    case m4a

    public var fileName: String {
        switch self {
            case .wav:
                "generated.wav"
            case .m4a:
                "generated.m4a"
        }
    }

    public var contentType: String {
        switch self {
            case .wav:
                "audio/wav"
            case .m4a:
                "audio/mp4"
        }
    }
}
