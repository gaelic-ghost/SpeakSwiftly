import Foundation

public struct RequestContext: Codable, Sendable, Equatable {
    public enum RequestPurpose: String, Codable, Sendable, Equatable {
        case speech
        case audioFile
    }

    public enum PrefacePolicy: String, Codable, Sendable, Equatable {
        case always
        case never
        case `default`
    }

    enum CodingKeys: String, CodingKey {
        case reqPurpose
        case source
        case topic
        case cwd
        case repoRoot = "repo_root"
        case attributes
        case prefacePolicy
    }

    public let reqPurpose: RequestPurpose
    public let source: String?
    public let topic: String?
    public let cwd: String?
    public let repoRoot: String?
    public let attributes: [String: String]
    public let prefacePolicy: PrefacePolicy?

    public init(
        reqPurpose: RequestPurpose,
        source: String? = nil,
        topic: String? = nil,
        cwd: String? = nil,
        repoRoot: String? = nil,
        attributes: [String: String] = [:],
        prefacePolicy: PrefacePolicy? = nil,
    ) {
        self.reqPurpose = reqPurpose
        self.source = source
        self.topic = topic
        self.cwd = Self.normalizedPath(cwd)
        self.repoRoot = Self.normalizedPath(repoRoot)
        self.attributes = attributes
        self.prefacePolicy = prefacePolicy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reqPurpose = try container.decode(RequestPurpose.self, forKey: .reqPurpose)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        cwd = try Self.normalizedPath(container.decodeIfPresent(String.self, forKey: .cwd))
        repoRoot = try Self.normalizedPath(container.decodeIfPresent(String.self, forKey: .repoRoot))
        attributes = try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        prefacePolicy = try container.decodeIfPresent(PrefacePolicy.self, forKey: .prefacePolicy)
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let standardized = NSString(string: trimmed).standardizingPath
        return standardized.isEmpty ? nil : standardized
    }
}
