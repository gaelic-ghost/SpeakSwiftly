import Foundation
import TextForSpeech

struct GeneratedFileManifest: Codable, Equatable {
    let version: Int
    let artifactID: String
    let createdAt: Date
    let voiceProfile: String
    let textProfile: SpeakSwiftly.TextProfileID?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestContext: SpeakSwiftly.RequestContext?
    let sampleRate: Int
    let audioFile: String
}

extension SpeakSwiftly {
    /// Metadata for one retained generated audio file.
    struct GeneratedFile: Codable, Equatable {
        let artifactID: String
        let createdAt: Date
        let voiceProfile: String
        let textProfile: SpeakSwiftly.TextProfileID?
        let sourceFormat: TextForSpeech.SourceFormat?
        let requestContext: SpeakSwiftly.RequestContext?
        let sampleRate: Int
        let filePath: String

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case createdAt = "created_at"
            case voiceProfile = "voice_profile"
            case textProfile = "text_profile"
            case sourceFormat = "source_format"
            case requestContext = "request_context"
            case sampleRate = "sample_rate"
            case filePath = "file_path"
        }

        init(
            artifactID: String,
            createdAt: Date,
            voiceProfile: String,
            textProfile: SpeakSwiftly.TextProfileID?,
            sourceFormat: TextForSpeech.SourceFormat?,
            requestContext: SpeakSwiftly.RequestContext?,
            sampleRate: Int,
            filePath: String,
        ) {
            self.artifactID = artifactID
            self.createdAt = createdAt
            self.voiceProfile = voiceProfile
            self.textProfile = textProfile
            self.sourceFormat = sourceFormat
            self.requestContext = requestContext
            self.sampleRate = sampleRate
            self.filePath = filePath
        }
    }
}

struct StoredGeneratedFile: Equatable {
    let manifest: GeneratedFileManifest
    let directoryURL: URL
    let audioURL: URL

    var summary: SpeakSwiftly.GeneratedFile {
        SpeakSwiftly.GeneratedFile(
            artifactID: manifest.artifactID,
            createdAt: manifest.createdAt,
            voiceProfile: manifest.voiceProfile,
            textProfile: manifest.textProfile,
            sourceFormat: manifest.sourceFormat,
            requestContext: manifest.requestContext,
            sampleRate: manifest.sampleRate,
            filePath: audioURL.standardizedFileURL.path,
        )
    }
}

struct GeneratedFileStore {
    static let directoryName = "generated-files"
    static let manifestFileName = "generated-file.json"
    static let audioFileName = "generated.wav"

    let rootURL: URL
    let fileManager: FileManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
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

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func createGeneratedFile(
        artifactID: String,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        sampleRate: Int,
        audioData: Data,
    ) throws -> StoredGeneratedFile {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .generatedFileAlreadyExists,
                message: "Generated file '\(artifactID)' already exists in the SpeakSwiftly generated-file store and cannot be overwritten.",
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let manifest = GeneratedFileManifest(
            version: 1,
            artifactID: artifactID,
            createdAt: Date(),
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
            sampleRate: sampleRate,
            audioFile: Self.audioFileName,
        )

        do {
            try audioData.write(to: audioURL(for: directoryURL), options: .atomic)
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL(for: directoryURL), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw WorkerError(
                code: .filesystemError,
                message: "Generated file '\(artifactID)' could not be written to disk. \(error.localizedDescription)",
            )
        }

        return StoredGeneratedFile(
            manifest: manifest,
            directoryURL: directoryURL,
            audioURL: audioURL(for: directoryURL),
        )
    }

    func loadGeneratedFile(id artifactID: String) throws -> StoredGeneratedFile {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .generatedFileNotFound,
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
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Generated file '\(artifactID)' exists, but its metadata could not be read. \(error.localizedDescription)",
            )
        }
    }

    func listGeneratedFiles() throws -> [SpeakSwiftly.GeneratedFile] {
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
    func removeGeneratedFile(id artifactID: String) throws -> SpeakSwiftly.GeneratedFile? {
        try ensureRootExists()

        let directoryURL = generatedFileDirectoryURL(for: artifactID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        let storedFile = try loadGeneratedFile(id: artifactID)

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Generated file '\(artifactID)' was found, but SpeakSwiftly could not remove its stored artifact directory at '\(directoryURL.path)'. \(error.localizedDescription)",
            )
        }

        return storedFile.summary
    }

    func generatedFileDirectoryURL(for artifactID: String) -> URL {
        rootURL.appendingPathComponent(encodedDirectoryName(for: artifactID), isDirectory: true)
    }

    func manifestURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    func audioURL(for directoryURL: URL, fileName: String = Self.audioFileName) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    private func encodedDirectoryName(for artifactID: String) -> String {
        artifactID.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
