import Foundation
import SpeakSwiftlyCore

public struct GeneratedFileManifest: Codable, Equatable, Sendable {
    public let version: Int
    public let artifactID: String
    public let createdAt: Date
    public let voiceProfile: String
    public let textProfile: String?
    public let sourceFormat: SourceFormat?
    public let requestContext: RequestContext?
    public let sampleRate: Int
    public let audioFormat: GeneratedAudioFileFormat
    public let contentType: String
    public let audioFile: String
}

public struct GeneratedFileSummary: Codable, Equatable, Sendable {
    public let artifactID: String
    public let createdAt: Date
    public let voiceProfile: String
    public let textProfile: String?
    public let sourceFormat: SourceFormat?
    public let requestContext: RequestContext?
    public let sampleRate: Int
    public let audioFormat: GeneratedAudioFileFormat
    public let contentType: String
    public let filePath: String
}

public struct StoredGeneratedFile: Equatable, Sendable {
    public let manifest: GeneratedFileManifest
    public let directoryURL: URL
    public let audioURL: URL

    public var summary: GeneratedFileSummary {
        GeneratedFileSummary(
            artifactID: manifest.artifactID,
            createdAt: manifest.createdAt,
            voiceProfile: manifest.voiceProfile,
            textProfile: manifest.textProfile,
            sourceFormat: manifest.sourceFormat,
            requestContext: manifest.requestContext,
            sampleRate: manifest.sampleRate,
            audioFormat: manifest.audioFormat,
            contentType: manifest.contentType,
            filePath: audioURL.standardizedFileURL.path,
        )
    }
}

public struct GeneratedFileStore: @unchecked Sendable {
    public static let directoryName = "generated-files"
    public static let manifestFileName = "generated-file.json"
    public static let defaultAudioFileName = GeneratedAudioFileFormat.wav.fileName

    public let rootURL: URL
    public let fileManager: FileManager
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = GeneratedFileStore.makeEncoder(),
        decoder: JSONDecoder = GeneratedFileStore.makeDecoder(),
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func createGeneratedFile(
        artifactID: String,
        voiceProfile: String,
        textProfile: String?,
        sourceFormat: SourceFormat?,
        requestContext: RequestContext?,
        sampleRate: Int,
        audioFormat: GeneratedAudioFileFormat = .wav,
        audioData: Data,
    ) throws -> StoredGeneratedFile {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw GeneratedFileStoreError.generatedFileAlreadyExists(
                message: "Generated file '\(artifactID)' already exists in the SpeakSwiftly generated-file store and cannot be overwritten.",
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let manifest = GeneratedFileManifest(
            version: 2,
            artifactID: artifactID,
            createdAt: Date(),
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
            sampleRate: sampleRate,
            audioFormat: audioFormat,
            contentType: audioFormat.contentType,
            audioFile: audioFormat.fileName,
        )

        do {
            try audioData.write(to: audioURL(for: directoryURL, fileName: manifest.audioFile), options: .atomic)
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL(for: directoryURL), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw GeneratedFileStoreError.filesystemError(
                message: "Generated file '\(artifactID)' could not be written to disk. \(error.localizedDescription)",
            )
        }

        return StoredGeneratedFile(
            manifest: manifest,
            directoryURL: directoryURL,
            audioURL: audioURL(for: directoryURL, fileName: manifest.audioFile),
        )
    }

    public func loadGeneratedFile(id artifactID: String) throws -> StoredGeneratedFile {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw GeneratedFileStoreError.generatedFileNotFound(
                message: "Generated file '\(artifactID)' was not found in the SpeakSwiftly generated-file store.",
            )
        }

        do {
            let manifestData = try Data(contentsOf: manifestURL(for: directoryURL))
            let manifest = try decoder.decode(GeneratedFileManifest.self, from: manifestData)
            return StoredGeneratedFile(
                manifest: manifest,
                directoryURL: directoryURL,
                audioURL: audioURL(for: directoryURL, fileName: manifest.audioFile),
            )
        } catch let storeError as GeneratedFileStoreError {
            throw storeError
        } catch {
            throw GeneratedFileStoreError.filesystemError(
                message: "Generated file '\(artifactID)' exists, but its metadata could not be read. \(error.localizedDescription)",
            )
        }
    }

    public func listGeneratedFiles() throws -> [GeneratedFileSummary] {
        try ensureRootExists()

        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        return urls
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .compactMap { directoryURL in
                do {
                    let manifestData = try Data(contentsOf: manifestURL(for: directoryURL))
                    let manifest = try decoder.decode(GeneratedFileManifest.self, from: manifestData)
                    return StoredGeneratedFile(
                        manifest: manifest,
                        directoryURL: directoryURL,
                        audioURL: audioURL(for: directoryURL, fileName: manifest.audioFile),
                    ).summary
                } catch {
                    return nil
                }
            }
    }

    @discardableResult
    public func removeGeneratedFile(id artifactID: String) throws -> GeneratedFileSummary? {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        let storedFile = try loadGeneratedFile(id: artifactID)

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw GeneratedFileStoreError.filesystemError(
                message: "Generated file '\(artifactID)' was found, but SpeakSwiftly could not remove its stored artifact directory at '\(directoryURL.path)'. \(error.localizedDescription)",
            )
        }

        return storedFile.summary
    }

    public func generatedFileDirectoryURL(for artifactID: String) -> URL {
        rootURL.appendingPathComponent(encodedDirectoryName(for: artifactID), isDirectory: true)
    }

    public func manifestURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    public func audioURL(for directoryURL: URL, fileName: String = Self.defaultAudioFileName) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    private func encodedDirectoryName(for artifactID: String) -> String {
        artifactID.utf8.map { String(format: "%02x", $0) }.joined()
    }
}

public enum GeneratedFileStoreError: Error, Sendable, Equatable {
    case generatedFileAlreadyExists(message: String)
    case generatedFileNotFound(message: String)
    case filesystemError(message: String)
}
