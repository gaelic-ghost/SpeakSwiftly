import Foundation
import SpeakSwiftlyFileAudioOutput

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

    /// Subscribes to sequenced generation-queue updates.
    func updates() async -> AsyncStream<SpeakSwiftly.GenerateUpdate> {
        await runtime.generateUpdates()
    }

    /// Returns a point-in-time read of the global generation queue.
    func snapshot() async -> SpeakSwiftly.GenerateSnapshot {
        await runtime.generateSnapshot()
    }

    /// Queues text for live speech output.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voiceProfile: The stored voice profile to use. When omitted, SpeakSwiftly uses the runtime default.
    ///   - textProfile: An optional text-normalization profile override.
    ///   - requestContext: Optional metadata that describes where the request came from and what it is related to.
    ///   - qwenPreModelTextChunking: Whether Qwen live playback should split text before model generation.
    ///   - output: Optional request-level destination override for this live generated-audio stream.
    ///     When omitted, SpeakSwiftly uses the runtime's configured audio output destination.
    /// - Returns: A request handle that can be observed for lifecycle and generation events.
    func speech(
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
        output: SpeakSwiftly.AudioOutputDestination? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        let requestID = UUID().uuidString
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        if let output {
            await runtime.setAudioOutputDestination(output, for: requestID)
        }
        return await runtime.submit(
            .queueSpeech(
                id: requestID,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .live,
                audioFormat: nil,
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
        requestContext: SpeakSwiftly.RequestContext? = nil,
        format: SpeakSwiftly.GeneratedAudioFileFormat = .wav,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueSpeech(
                id: UUID().uuidString,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .file,
                audioFormat: format,
                requestContext: requestContext,
                qwenPreModelTextChunking: nil,
            ),
        )
    }

    /// Generates speech audio as canonical chunk metadata plus Float32 PCM samples.
    ///
    /// Use this lower-level surface when the caller owns the output boundary, such as an
    /// HTTP response stream, LAN transport sender, file encoder, benchmark, or custom player.
    func audioStream(
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
    ) async -> SpeakSwiftly.GeneratedAudioStream {
        let requestID = UUID().uuidString
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submitGeneratedAudioStream(
            requestID: requestID,
            text: text,
            profileName: resolvedVoiceProfile,
            textProfileID: textProfile,
            requestContext: requestContext,
            qwenPreModelTextChunking: qwenPreModelTextChunking,
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
