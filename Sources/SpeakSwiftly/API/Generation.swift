import Foundation
import TextForSpeech

// MARK: - Generation API

public extension SpeakSwiftly.Runtime {
    func speak(
        text: String,
        with profileName: String,
        as job: SpeakSwiftly.Job,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .queueSpeech(
                id: id,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: job,
                textContext: textContext,
                sourceFormat: sourceFormat
            )
        )
    }
}
