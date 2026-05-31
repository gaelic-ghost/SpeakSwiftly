import Foundation
import Network
import SpeakSwiftlyCore

public enum NetworkAudioBonjour {
    public static let serviceType = "_spswift-audio._tcp"
    public static let domain = "local"
    public static let protocolVersion = 1
}

public struct NetworkAudioCapabilities: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let sampleFormats: [GeneratedAudioSampleFormat]
    public let sampleRates: [Int]
    public let channelCounts: [Int]

    public init(
        protocolVersion: Int = NetworkAudioBonjour.protocolVersion,
        sampleFormats: [GeneratedAudioSampleFormat] = [.float32PCM],
        sampleRates: [Int] = [24000],
        channelCounts: [Int] = [1],
    ) {
        self.protocolVersion = protocolVersion
        self.sampleFormats = sampleFormats
        self.sampleRates = sampleRates
        self.channelCounts = channelCounts
    }

    public init(txtRecord: NWTXTRecord) {
        self.init(
            protocolVersion: txtRecord.integerValue(for: "proto") ?? NetworkAudioBonjour.protocolVersion,
            sampleFormats: txtRecord.csvValue(for: "fmt").compactMap(GeneratedAudioSampleFormat.init(rawValue:)),
            sampleRates: txtRecord.csvValue(for: "rate").compactMap(Int.init),
            channelCounts: txtRecord.csvValue(for: "ch").compactMap(Int.init),
        )
    }

    public var txtRecord: NWTXTRecord {
        NWTXTRecord([
            "txtvers": "1",
            "proto": String(protocolVersion),
            "fmt": sampleFormats.map(\.rawValue).joined(separator: ","),
            "rate": sampleRates.map(String.init).joined(separator: ","),
            "ch": channelCounts.map(String.init).joined(separator: ","),
        ])
    }
}

public struct NetworkAudioServiceAdvertisement: Sendable, Equatable {
    public let name: String
    public let type: String
    public let domain: String
    public let capabilities: NetworkAudioCapabilities

    public init(
        name: String,
        type: String = NetworkAudioBonjour.serviceType,
        domain: String = NetworkAudioBonjour.domain,
        capabilities: NetworkAudioCapabilities = NetworkAudioCapabilities(),
    ) {
        self.name = name
        self.type = type
        self.domain = domain
        self.capabilities = capabilities
    }

    public var listenerService: NWListener.Service {
        NWListener.Service(
            name: name,
            type: type,
            domain: domain,
            txtRecord: capabilities.txtRecord,
        )
    }
}

private extension NWTXTRecord {
    func csvValue(for key: String) -> [String] {
        guard let value = self[key], !value.isEmpty else {
            return []
        }

        return value.split(separator: ",").map(String.init)
    }

    func integerValue(for key: String) -> Int? {
        self[key].flatMap(Int.init)
    }
}
