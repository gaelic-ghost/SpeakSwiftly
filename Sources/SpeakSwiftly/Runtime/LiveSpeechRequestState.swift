import Foundation

final class LiveSpeechRequestState: @unchecked Sendable {
    let request: WorkerRequest
    let text: String
    let profileName: String
    let textProfileID: String?
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
        let text: String
        let profileName: String
        let textProfileID: String?
        let requestContext: SpeakSwiftly.RequestContext?
        switch request {
            case let .queueSpeech(
            id: _,
            text: requestText,
            profileName: requestProfileName,
            textProfileID: requestTextProfileID,
            jobType: jobType,
            audioFormat: _,
            requestContext: speechRequestContext,
            qwenPreModelTextChunking: _,
        ) where jobType == .live || jobType == .stream:
                text = requestText
                profileName = requestProfileName
                textProfileID = requestTextProfileID
                requestContext = speechRequestContext
            case let .replayRecentAudio(
            id: _,
            recentAudioID: _,
            text: requestText,
            profileName: requestProfileName,
            requestContext: replayRequestContext,
        ):
                text = requestText
                profileName = requestProfileName
                textProfileID = nil
                requestContext = replayRequestContext
            default:
                fatalError(
                    "SpeakSwiftly attempted to create speech request state for request '\(request.id)' (\(request.opName)), but that request is not a live playback, generated-audio stream, or recent-audio replay request. This indicates a runtime queueing bug.",
                )
        }

        self.request = request
        self.text = text
        self.profileName = profileName
        self.textProfileID = textProfileID
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
