import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon
import TextForSpeech

// MARK: - Generated File Logic

extension SpeakSwiftly.Runtime {
    func handleQueueSpeechFileGeneration(
        requestID id: String,
        op: String,
        artifactID: String,
        text: String,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async throws -> SpeakSwiftly.GeneratedFile {
        let residentInputs = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: voiceProfile,
        )
        let residentModel = residentInputs.model

        let normalizedText = try await normalizerRef.speechText(
            text,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
            textProfileID: textProfile,
        )

        await emitProgress(id: id, stage: .generatingFileAudio)
        let generationStartedAt = dependencies.now()
        let stream = residentGenerationStream(
            requestID: id,
            text: normalizedText,
            inputs: residentInputs,
            generationParameters: GenerationPolicy.residentParameters(
                for: speechBackend,
                text: normalizedText,
            ),
            streamingInterval: PlaybackConfiguration.residentStreamingInterval(
                for: speechBackend,
                cadenceProfile: .standard,
            ),
        )
        var audio = [Float]()
        for try await chunk in stream {
            try Task.checkCancellation()
            audio.append(contentsOf: chunk)
        }
        await logRequestEvent(
            "generated_file_audio_rendered",
            requestID: id,
            op: op,
            profileName: voiceProfile,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager
            .temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempAudioURL = tempDirectory.appendingPathComponent(GeneratedFileStore.audioFileName)
        try dependencies.writeWAV(audio, residentModel.sampleRate, tempAudioURL)
        let audioData = try Data(contentsOf: tempAudioURL)
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingGeneratedFile)
        let writeStartedAt = dependencies.now()
        let generatedFile = try generatedFileStore.createGeneratedFile(
            artifactID: artifactID,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
            sampleRate: residentModel.sampleRate,
            audioData: audioData,
        )
        await logRequestEvent(
            "generated_file_written",
            requestID: id,
            op: op,
            profileName: voiceProfile,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "path": .string(generatedFile.audioURL.path),
                "duration_ms": .int(elapsedMS(since: writeStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
            ],
        )

        return generatedFile.summary
    }

    func residentGenerationStream(
        requestID: String,
        text: String,
        inputs: ResidentSpeechInputs,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        switch inputs {
            case let .qwenRaw(model, _, materialization, refAudio):
                qwenGenerationStream(
                    requestID: requestID,
                    model: model,
                    text: text,
                    materialization: materialization,
                    refAudio: refAudio,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .qwenPrepared(model, _, conditioning):
                qwenGenerationStream(
                    requestID: requestID,
                    model: model,
                    text: text,
                    conditioning: conditioning,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .chatterboxTurbo(model, _, refAudio):
                chatterboxGenerationStream(
                    requestID: requestID,
                    model: model,
                    text: text,
                    refAudio: refAudio,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .marvis(model, _, voice):
                marvisGenerationStream(
                    model: model,
                    text: text,
                    voice: voice,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
        }
    }

    func residentLiveGenerationStream(
        requestID: String,
        op: String?,
        profileName: String,
        text: String,
        plannedTextChunks: [LiveSpeechTextChunk]?,
        inputs: ResidentSpeechInputs,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        switch inputs {
            case let .qwenRaw(model, _, materialization, refAudio):
                qwenLiveGenerationStream(
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    model: model,
                    text: text,
                    plannedChunks: plannedTextChunks,
                    materialization: materialization,
                    refAudio: refAudio,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .qwenPrepared(model, _, conditioning):
                qwenLiveGenerationStream(
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    model: model,
                    text: text,
                    plannedChunks: plannedTextChunks,
                    conditioning: conditioning,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .chatterboxTurbo(model, _, refAudio):
                chatterboxGenerationStream(
                    requestID: requestID,
                    model: model,
                    text: text,
                    refAudio: refAudio,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .marvis(model, _, voice):
                marvisGenerationStream(
                    model: model,
                    text: text,
                    voice: voice,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
        }
    }
}
