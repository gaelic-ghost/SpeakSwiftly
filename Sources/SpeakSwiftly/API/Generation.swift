import Foundation
import TextForSpeech

// MARK: - Generation API

public extension SpeakSwiftly {
    struct Generate: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    nonisolated var generate: SpeakSwiftly.Generate {
        SpeakSwiftly.Generate(runtime: self)
    }
}

public extension SpeakSwiftly.Generate {
    func speech(
        text: String,
        with profileName: SpeakSwiftly.Name,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: id,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: .live,
                textContext: textContext,
                sourceFormat: sourceFormat
            )
        )
    }

    func audio(
        text: String,
        with profileName: SpeakSwiftly.Name,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: id,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: .file,
                textContext: textContext,
                sourceFormat: sourceFormat
            )
        )
    }

    func batch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: SpeakSwiftly.Name,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueBatch(
                id: id,
                profileName: profileName,
                items: SpeakSwiftly.Runtime.resolveBatchItems(items, batchID: id)
            )
        )
    }
}
