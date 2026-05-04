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
    ///   - voiceProfile: The stored voice profile to use. When omitted, SpeakSwiftly uses the runtime default.
    ///   - textProfile: An optional text-normalization profile override.
    ///   - inputTextContext: Optional metadata that describes how the input text should be interpreted.
    ///   - requestContext: Optional metadata that describes where the request came from and what it is related to.
    ///   - qwenPreModelTextChunking: Whether Qwen live playback should split text before model generation.
    /// - Returns: A request handle that can be observed for lifecycle and generation events.
    func speech(
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        inputTextContext: SpeakSwiftly.InputTextContext? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .live,
                inputTextContext: inputTextContext,
                requestContext: requestContext,
                qwenPreModelTextChunking: qwenPreModelTextChunking,
            ),
        )
    }

    /// Queues text for retained audio-file generation.
    ///
    /// Use this when you want a generated artifact to keep and inspect later instead of
    /// immediate live playback.
    func audio(
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        inputTextContext: SpeakSwiftly.InputTextContext? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .file,
                inputTextContext: inputTextContext,
                requestContext: requestContext,
                qwenPreModelTextChunking: nil,
            ),
        )
    }

    /// Queues a batch of retained audio-file generation requests under one voice profile.
    ///
    /// - Parameters:
    ///   - items: The items to synthesize.
    ///   - voiceProfile: The stored voice profile to use for every item in the batch. When omitted,
    ///     SpeakSwiftly uses the runtime default.
    /// - Returns: A request handle whose terminal success payload includes the created batch.
    func batch(
        _ items: [SpeakSwiftly.BatchItem],
        voiceProfile: SpeakSwiftly.Name? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        let requestID = UUID().uuidString
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueBatch(
                id: requestID,
                profileName: resolvedVoiceProfile,
                items: SpeakSwiftly.Runtime.resolveBatchItems(items, batchID: requestID),
            ),
        )
    }
}

extension SpeakSwiftly.Runtime {
    func resolveGenerationVoiceProfile(_ profileName: SpeakSwiftly.Name?) -> SpeakSwiftly.Name {
        let trimmed = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultVoiceProfileName : trimmed
    }
}
