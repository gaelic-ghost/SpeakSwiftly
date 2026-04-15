import Foundation
import TextForSpeech

final class LiveSpeechRequestState: @unchecked Sendable {
    let request: WorkerRequest
    let text: String
    let profileName: String
    let textProfileName: String?
    let textContext: TextForSpeech.Context?
    let sourceFormat: TextForSpeech.SourceFormat?
    let normalizedText: String
    let textFeatures: SpeechTextDeepTraceFeatures
    let textSections: [SpeechTextDeepTraceSection]

    init(
        request: WorkerRequest,
        normalizedText: String,
        textFeatures: SpeechTextDeepTraceFeatures,
        textSections: [SpeechTextDeepTraceSection],
    ) {
        guard case let .queueSpeech(
            id: _,
            text: text,
            profileName: profileName,
            textProfileName: textProfileName,
            jobType: .live,
            textContext: textContext,
            sourceFormat: sourceFormat,
        ) = request else {
            fatalError(
                "SpeakSwiftly attempted to create live speech request state for request '\(request.id)' (\(request.opName)), but that request does not require live playback. This indicates a runtime queueing bug.",
            )
        }

        self.request = request
        self.text = text
        self.profileName = profileName
        self.textProfileName = textProfileName
        self.textContext = textContext
        self.sourceFormat = sourceFormat
        self.normalizedText = normalizedText
        self.textFeatures = textFeatures
        self.textSections = textSections
    }

    var id: String {
        request.id
    }

    var op: String {
        request.opName
    }
}
