import Foundation

public extension SpeakSwiftlyNormalization {
    enum PersistenceError: Swift.Error, Sendable, Equatable, LocalizedError {
        case missingPersistenceURL
        case unsupportedPersistedStateVersion(Int)
        case couldNotRead(URL, String)
        case couldNotDecode(URL, String)
        case couldNotCreateDirectory(URL, String)
        case couldNotWrite(URL, String)

        public var errorDescription: String? {
            switch self {
                case .missingPersistenceURL:
                    "SpeakSwiftly normalization could not load or save profiles because no persistence URL was configured for this runtime."
                case let .unsupportedPersistedStateVersion(version):
                    "SpeakSwiftly normalization could not load the persisted profile state because archive version \(version) is not supported by this build."
                case let .couldNotRead(url, details):
                    "SpeakSwiftly normalization could not read persisted profiles from '\(url.path)'. \(details)"
                case let .couldNotDecode(url, details):
                    "SpeakSwiftly normalization could not decode persisted profiles from '\(url.path)'. \(details)"
                case let .couldNotCreateDirectory(url, details):
                    "SpeakSwiftly normalization could not create the directory for persisted profiles at '\(url.path)'. \(details)"
                case let .couldNotWrite(url, details):
                    "SpeakSwiftly normalization could not write persisted profiles to '\(url.path)'. \(details)"
            }
        }
    }

    enum ProfileError: Swift.Error, Sendable, Equatable, LocalizedError {
        case profileAlreadyExists(String)
        case profileNotFound(String)
        case replacementNotFound(String, profileID: String)

        public var errorDescription: String? {
            switch self {
                case let .profileAlreadyExists(id):
                    "SpeakSwiftly could not create text profile '\(id)' because a stored profile with that identifier already exists."
                case let .profileNotFound(id):
                    "SpeakSwiftly could not find stored text profile '\(id)'."
                case let .replacementNotFound(replacementID, profileID):
                    "SpeakSwiftly could not find text replacement '\(replacementID)' in profile '\(profileID)'."
            }
        }
    }

    enum SummaryError: Swift.Error, Sendable, Equatable, LocalizedError {
        case missingCredential(String)
        case providerUnavailable(String)
        case providerFailed(String)

        public var errorDescription: String? {
            switch self {
                case let .missingCredential(message),
                     let .providerUnavailable(message),
                     let .providerFailed(message):
                    message
            }
        }
    }
}
