import Foundation
import TextForSpeech

// MARK: - SpeakSwiftly.Generate

public extension SpeakSwiftly {
    // MARK: Generate Handle

    /// Submits generation work for live playback or retained file output.
    struct Generate: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the generation surface for this runtime.
    nonisolated var generate: SpeakSwiftly.Generate {
        SpeakSwiftly.Generate(runtime: self)
    }
}

public extension SpeakSwiftly.Generate {
    // MARK: Operations

    /// Queues text for live speech playback.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - profileName: The stored voice profile to use.
    ///   - textProfileName: An optional text-normalization profile override.
    ///   - textContext: Optional normalization context metadata.
    ///   - sourceFormat: Optional format hint for the source text.
    /// - Returns: A request handle that can be observed for lifecycle and generation events.
    func speech(
        text: String,
        with profileName: SpeakSwiftly.Name,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: .live,
                textContext: textContext,
                sourceFormat: sourceFormat,
            ),
        )
    }

    /// Queues text for retained audio-file generation.
    ///
    /// Use this when you want a generated artifact to keep and inspect later instead of
    /// immediate live playback.
    func audio(
        text: String,
        with profileName: SpeakSwiftly.Name,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: .file,
                textContext: textContext,
                sourceFormat: sourceFormat,
            ),
        )
    }

    /// Queues a batch of retained audio-file generation requests under one voice profile.
    ///
    /// - Parameters:
    ///   - items: The items to synthesize.
    ///   - profileName: The stored voice profile to use for every item in the batch.
    /// - Returns: A request handle whose terminal success payload includes the created batch.
    func batch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        let requestID = UUID().uuidString
        return await runtime.submit(
            .queueBatch(
                id: requestID,
                profileName: profileName,
                items: SpeakSwiftly.Runtime.resolveBatchItems(items, batchID: requestID),
            ),
        )
    }
}
