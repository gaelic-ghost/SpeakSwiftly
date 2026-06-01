import Foundation
import SpeakSwiftlyFileAudioOutput
import TextForSpeech

public extension SpeakSwiftly {
    typealias GeneratedAudioFileFormat = SpeakSwiftlyFileAudioOutput.GeneratedAudioFileFormat

    /// Metadata for one retained generated audio file.
    struct GeneratedFile: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case createdAt = "created_at"
            case voiceProfile = "voice_profile"
            case textProfile = "text_profile"
            case sourceFormat = "source_format"
            case requestContext = "request_context"
            case sampleRate = "sample_rate"
            case audioFormat = "audio_format"
            case contentType = "content_type"
            case filePath = "file_path"
        }

        let artifactID: String
        let createdAt: Date
        let voiceProfile: String
        let textProfile: SpeakSwiftly.TextProfileID?
        let sourceFormat: TextForSpeech.SourceFormat?
        let requestContext: SpeakSwiftly.RequestContext?
        let sampleRate: Int
        let audioFormat: SpeakSwiftly.GeneratedAudioFileFormat
        let contentType: String
        let filePath: String

        init(
            artifactID: String,
            createdAt: Date,
            voiceProfile: String,
            textProfile: SpeakSwiftly.TextProfileID?,
            sourceFormat: TextForSpeech.SourceFormat?,
            requestContext: SpeakSwiftly.RequestContext?,
            sampleRate: Int,
            audioFormat: SpeakSwiftly.GeneratedAudioFileFormat,
            contentType: String,
            filePath: String,
        ) {
            self.artifactID = artifactID
            self.createdAt = createdAt
            self.voiceProfile = voiceProfile
            self.textProfile = textProfile
            self.sourceFormat = sourceFormat
            self.requestContext = requestContext
            self.sampleRate = sampleRate
            self.audioFormat = audioFormat
            self.contentType = contentType
            self.filePath = filePath
        }
    }
}

typealias GeneratedFileStore = SpeakSwiftlyFileAudioOutput.GeneratedFileStore
typealias StoredGeneratedFile = SpeakSwiftlyFileAudioOutput.StoredGeneratedFile
typealias GeneratedFileManifest = SpeakSwiftlyFileAudioOutput.GeneratedFileManifest
typealias GeneratedFileStoreError = SpeakSwiftlyFileAudioOutput.GeneratedFileStoreError
typealias GeneratedAudioFileOutputError = SpeakSwiftlyFileAudioOutput.GeneratedAudioFileOutputError

extension SpeakSwiftly.GeneratedFile {
    init(_ summary: SpeakSwiftlyFileAudioOutput.GeneratedFileSummary) {
        self.init(
            artifactID: summary.artifactID,
            createdAt: summary.createdAt,
            voiceProfile: summary.voiceProfile,
            textProfile: summary.textProfile,
            sourceFormat: summary.sourceFormat,
            requestContext: summary.requestContext,
            sampleRate: summary.sampleRate,
            audioFormat: summary.audioFormat,
            contentType: summary.contentType,
            filePath: summary.filePath,
        )
    }
}

extension GeneratedFileStoreError {
    var workerError: WorkerError {
        switch self {
            case let .generatedFileAlreadyExists(message):
                WorkerError(code: .generatedFileAlreadyExists, message: message)
            case let .generatedFileNotFound(message):
                WorkerError(code: .generatedFileNotFound, message: message)
            case let .filesystemError(message):
                WorkerError(code: .filesystemError, message: message)
        }
    }
}

extension GeneratedAudioFileOutputError {
    var workerError: WorkerError {
        switch self {
            case let .invalidAudio(message):
                WorkerError(code: .filesystemError, message: message)
        }
    }
}
