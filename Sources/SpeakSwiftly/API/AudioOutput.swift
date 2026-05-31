import Foundation
import SpeakSwiftlyCore
import SpeakSwiftlyHTTPAudioOutput
import SpeakSwiftlyNetworkAudioOutput
import SpeakSwiftlyPlayback

public extension SpeakSwiftly {
    typealias GeneratedAudioChunk = SpeakSwiftlyCore.GeneratedAudioChunk
    typealias GeneratedAudioChunkStream = SpeakSwiftlyCore.GeneratedAudioChunkStream
    typealias GeneratedAudioSampleFormat = SpeakSwiftlyCore.GeneratedAudioSampleFormat
    typealias GeneratedAudioOutputError = SpeakSwiftlyCore.GeneratedAudioOutputError
    typealias LocalPlaybackAudioOutput = SpeakSwiftlyPlayback.LocalPlaybackAudioOutput
    typealias HTTPGeneratedAudioFrame = SpeakSwiftlyHTTPAudioOutput.HTTPGeneratedAudioFrame
    typealias HTTPGeneratedAudioFrameHeader = SpeakSwiftlyHTTPAudioOutput.HTTPGeneratedAudioFrameHeader
    typealias NetworkAudioEndpoint = SpeakSwiftlyNetworkAudioOutput.NetworkAudioEndpoint
    typealias NetworkGeneratedAudioFrame = SpeakSwiftlyNetworkAudioOutput.NetworkGeneratedAudioFrame
    typealias NetworkGeneratedAudioFrameCodec = SpeakSwiftlyNetworkAudioOutput.NetworkGeneratedAudioFrameCodec

    enum AudioOutputDestination: Codable, Sendable, Equatable {
        case localPlayback
        case httpResponseStream
        case networkStream(host: String, port: UInt16)

        enum CodingKeys: String, CodingKey {
            case kind
            case host
            case port
        }

        enum Kind: String, Codable {
            case localPlayback = "local_playback"
            case httpResponseStream = "http_response_stream"
            case networkStream = "network_stream"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
                case .localPlayback:
                    self = .localPlayback
                case .httpResponseStream:
                    self = .httpResponseStream
                case .networkStream:
                    let host = try container.decode(String.self, forKey: .host)
                    let port = try container.decode(UInt16.self, forKey: .port)
                    self = .networkStream(host: host, port: port)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
                case .localPlayback:
                    try container.encode(Kind.localPlayback, forKey: .kind)
                case .httpResponseStream:
                    try container.encode(Kind.httpResponseStream, forKey: .kind)
                case let .networkStream(host, port):
                    try container.encode(Kind.networkStream, forKey: .kind)
                    try container.encode(host, forKey: .host)
                    try container.encode(port, forKey: .port)
            }
        }
    }
}
