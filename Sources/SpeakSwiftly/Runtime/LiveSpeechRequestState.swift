import Foundation
import TextForSpeech

final class LiveSpeechRequestState: @unchecked Sendable {
    let request: WorkerRequest
    let text: String
    let profileName: String
    let textProfileID: String?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestContext: SpeakSwiftly.RequestContext?
    let normalizedText: String
    let normalizedLiveChunks: [LiveSpeechTextChunk]?
    let textFeatures: SpeechTextDeepTraceFeatures
    let textSections: [SpeechTextDeepTraceSection]
    let playbackTuningProfile: PlaybackTuningProfile
    let residentStreamingCadenceProfile: SpeakSwiftly.Runtime.PlaybackConfiguration.ResidentStreamingCadenceProfile
    let residentStreamingInterval: Double

    var id: String {
        request.id
    }

    var op: String {
        request.opName
    }

    var kind: SpeakSwiftly.RequestKind {
        request.requestKind
    }

    var voiceProfile: String {
        profileName
    }

    init(
        request: WorkerRequest,
        normalizedText: String,
        normalizedLiveChunks: [LiveSpeechTextChunk]?,
        textFeatures: SpeechTextDeepTraceFeatures,
        textSections: [SpeechTextDeepTraceSection],
        playbackTuningProfile: PlaybackTuningProfile,
        residentStreamingCadenceProfile: SpeakSwiftly.Runtime.PlaybackConfiguration.ResidentStreamingCadenceProfile,
        residentStreamingInterval: Double,
    ) {
        guard case let .queueSpeech(
            id: _,
            text: text,
            profileName: profileName,
            textProfileID: textProfileID,
            jobType: .live,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
            qwenPreModelTextChunking: _,
        ) = request else {
            fatalError(
                "SpeakSwiftly attempted to create live speech request state for request '\(request.id)' (\(request.opName)), but that request does not require live playback. This indicates a runtime queueing bug.",
            )
        }

        self.request = request
        self.text = text
        self.profileName = profileName
        self.textProfileID = textProfileID
        self.sourceFormat = sourceFormat
        self.requestContext = requestContext
        self.normalizedText = normalizedText
        self.normalizedLiveChunks = normalizedLiveChunks
        self.textFeatures = textFeatures
        self.textSections = textSections
        self.playbackTuningProfile = playbackTuningProfile
        self.residentStreamingCadenceProfile = residentStreamingCadenceProfile
        self.residentStreamingInterval = residentStreamingInterval
    }
}
