public enum TextFormat: String, Codable, CaseIterable, Sendable, Hashable {
    case plain = "plain_text"
    case markdown
    case html
    case log
    case cli = "cli_output"
    case list
}

public enum SourceFormat: String, Codable, CaseIterable, Sendable, Hashable {
    case generic = "source_code"
    case swift = "swift_source"
    case python = "python_source"
    case rust = "rust_source"

    public func matches(_ other: Self) -> Bool {
        self == .generic || self == other
    }
}
