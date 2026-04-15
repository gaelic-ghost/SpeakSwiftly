import Foundation
import TextForSpeech

final class LiveSpeechRequestState: @unchecked Sendable {
    let request: WorkerRequest
    let normalizedText: String
    let textFeatures: SpeechTextDeepTraceFeatures
    let textSections: [SpeechTextDeepTraceSection]

    init(
        request: WorkerRequest,
        normalizedText: String,
        textFeatures: SpeechTextDeepTraceFeatures,
        textSections: [SpeechTextDeepTraceSection],
    ) {
        self.request = request
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

    var text: String {
        switch request {
            case .queueSpeech(id: _, text: let text, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
                text
            default:
                ""
        }
    }

    var profileName: String {
        request.profileName ?? "unknown-profile"
    }

    var textProfileName: String? {
        request.textProfileName
    }

    var textContext: TextForSpeech.Context? {
        request.textContext
    }

    var sourceFormat: TextForSpeech.SourceFormat? {
        request.sourceFormat
    }
}
