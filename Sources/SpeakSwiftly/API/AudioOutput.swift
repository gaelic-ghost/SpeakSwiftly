import Foundation
import SpeakSwiftlyCore
import SpeakSwiftlyHTTPAudioOutput
import SpeakSwiftlyNetworkAudioOutput
import SpeakSwiftlyPlayback

public extension SpeakSwiftly {
    typealias GeneratedAudioChunk = SpeakSwiftlyCore.GeneratedAudioChunk
    typealias GeneratedAudioChunkStream = SpeakSwiftlyCore.GeneratedAudioChunkStream
    typealias GeneratedAudioChunkStreams = SpeakSwiftlyCore.GeneratedAudioChunkStreams
    typealias GeneratedAudioSampleFormat = SpeakSwiftlyCore.GeneratedAudioSampleFormat
    typealias GeneratedAudioOutputError = SpeakSwiftlyCore.GeneratedAudioOutputError
    typealias RecentGeneratedAudioBufferState = SpeakSwiftlyCore.RecentGeneratedAudioBufferState
    typealias RecentGeneratedAudioItem = SpeakSwiftlyCore.RecentGeneratedAudioItem
    typealias RecentGeneratedAudioMetadata = SpeakSwiftlyCore.RecentGeneratedAudioMetadata
    typealias RecentGeneratedAudioReplayMode = SpeakSwiftlyCore.RecentGeneratedAudioReplayMode
    typealias RecentGeneratedAudioRetentionPolicy = SpeakSwiftlyCore.RecentGeneratedAudioRetentionPolicy
    typealias RecentGeneratedAudioSnapshot = SpeakSwiftlyCore.RecentGeneratedAudioSnapshot
    typealias RecentGeneratedAudioStore = SpeakSwiftlyCore.RecentGeneratedAudioStore
    typealias LocalPlaybackAudioOutput = SpeakSwiftlyPlayback.LocalPlaybackAudioOutput
    typealias HTTPGeneratedAudioFrame = SpeakSwiftlyHTTPAudioOutput.HTTPGeneratedAudioFrame
    typealias HTTPGeneratedAudioFrameHeader = SpeakSwiftlyHTTPAudioOutput.HTTPGeneratedAudioFrameHeader
    typealias NetworkAudioBonjour = SpeakSwiftlyNetworkAudioOutput.NetworkAudioBonjour
    typealias NetworkAudioCapabilities = SpeakSwiftlyNetworkAudioOutput.NetworkAudioCapabilities
    typealias NetworkAudioDestination = SpeakSwiftlyNetworkAudioOutput.NetworkAudioDestination
    typealias NetworkAudioDestinationBrowser = SpeakSwiftlyNetworkAudioOutput.NetworkAudioDestinationBrowser
    typealias NetworkAudioDestinationBrowserState = SpeakSwiftlyNetworkAudioOutput.NetworkAudioDestinationBrowserState
    typealias NetworkAudioEndpoint = SpeakSwiftlyNetworkAudioOutput.NetworkAudioEndpoint
    typealias NetworkAudioServiceAdvertisement = SpeakSwiftlyNetworkAudioOutput.NetworkAudioServiceAdvertisement
    typealias NetworkAudioInboundStream = SpeakSwiftlyNetworkAudioOutput.NetworkAudioInboundStream
    typealias NetworkAudioLengthPrefixedFrameCodec = SpeakSwiftlyNetworkAudioOutput.NetworkAudioLengthPrefixedFrameCodec
    typealias NetworkAudioStreamFrame = SpeakSwiftlyNetworkAudioOutput.NetworkAudioStreamFrame
    typealias NetworkAudioStreamHandshake = SpeakSwiftlyNetworkAudioOutput.NetworkAudioStreamHandshake
    typealias NetworkAudioStreamListener = SpeakSwiftlyNetworkAudioOutput.NetworkAudioStreamListener
    typealias NetworkAudioStreamSender = SpeakSwiftlyNetworkAudioOutput.NetworkAudioStreamSender
    typealias NetworkAudioStreamState = SpeakSwiftlyNetworkAudioOutput.NetworkAudioStreamState
    typealias NetworkGeneratedAudioFrame = SpeakSwiftlyNetworkAudioOutput.NetworkGeneratedAudioFrame
    typealias NetworkGeneratedAudioFrameCodec = SpeakSwiftlyNetworkAudioOutput.NetworkGeneratedAudioFrameCodec
    typealias LocalGeneratedAudioPlayer = SpeakSwiftlyPlayback.LocalGeneratedAudioPlayer

    enum AudioOutputDestination: Codable, Sendable, Equatable {
        case localPlayback
        case httpResponseStream
        case networkStream(host: String, port: UInt16)
        case networkService(name: String, type: String = NetworkAudioBonjour.serviceType, domain: String = NetworkAudioBonjour.domain)

        enum CodingKeys: String, CodingKey {
            case kind
            case host
            case port
            case name
            case type
            case domain
        }

        enum Kind: String, Codable {
            case localPlayback = "local_playback"
            case httpResponseStream = "http_response_stream"
            case networkStream = "network_stream"
            case networkService = "network_service"
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
                case .networkService:
                    let name = try container.decode(String.self, forKey: .name)
                    let type = try container.decode(String.self, forKey: .type)
                    let domain = try container.decode(String.self, forKey: .domain)
                    self = .networkService(name: name, type: type, domain: domain)
            }
        }

        public init(networkEndpoint endpoint: NetworkAudioEndpoint) {
            switch endpoint {
                case let .hostPort(host, port):
                    self = .networkStream(host: host, port: port)
                case let .bonjourService(name, type, domain):
                    self = .networkService(name: name, type: type, domain: domain)
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
                case let .networkService(name, type, domain):
                    try container.encode(Kind.networkService, forKey: .kind)
                    try container.encode(name, forKey: .name)
                    try container.encode(type, forKey: .type)
                    try container.encode(domain, forKey: .domain)
            }
        }
    }
}
