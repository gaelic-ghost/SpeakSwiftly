import Foundation
import TextForSpeech

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
    ///   - voiceProfile: The stored voice profile to use.
    ///   - textProfile: An optional text-normalization profile override.
    ///   - inputTextContext: Optional metadata that describes how the input text should be interpreted.
    ///   - requestContext: Optional metadata that describes where the request came from and what it is related to.
    /// - Returns: A request handle that can be observed for lifecycle and generation events.
    func speech(
        text: String,
        voiceProfile: SpeakSwiftly.Name,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        inputTextContext: SpeakSwiftly.InputTextContext? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: voiceProfile,
                textProfileID: textProfile,
                jobType: .live,
                inputTextContext: inputTextContext,
                requestContext: requestContext,
            ),
        )
    }

    /// Queues text for retained audio-file generation.
    ///
    /// Use this when you want a generated artifact to keep and inspect later instead of
    /// immediate live playback.
    func audio(
        text: String,
        voiceProfile: SpeakSwiftly.Name,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        inputTextContext: SpeakSwiftly.InputTextContext? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: voiceProfile,
                textProfileID: textProfile,
                jobType: .file,
                inputTextContext: inputTextContext,
                requestContext: requestContext,
            ),
        )
    }

    /// Queues a batch of retained audio-file generation requests under one voice profile.
    ///
    /// - Parameters:
    ///   - items: The items to synthesize.
    ///   - voiceProfile: The stored voice profile to use for every item in the batch.
    /// - Returns: A request handle whose terminal success payload includes the created batch.
    func batch(
        _ items: [SpeakSwiftly.BatchItem],
        voiceProfile: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        let requestID = UUID().uuidString
        return await runtime.submit(
            .queueBatch(
                id: requestID,
                profileName: voiceProfile,
                items: SpeakSwiftly.Runtime.resolveBatchItems(items, batchID: requestID),
            ),
        )
    }
}
