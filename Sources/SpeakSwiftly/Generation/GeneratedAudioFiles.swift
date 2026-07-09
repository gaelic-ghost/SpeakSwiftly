import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon
import SpeakSwiftlyFileAudioOutput
import TextForSpeech

// MARK: - Generated Audio Files

extension SpeakSwiftly.Runtime {
    func handleQueueSpeechFileGeneration(
        requestID id: String,
        op: String,
        artifactID: String,
        text: String,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        requestContext: SpeakSwiftly.RequestContext?,
        audioFormat: SpeakSwiftly.GeneratedAudioFileFormat,
    ) async throws -> SpeakSwiftly.GeneratedFile {
        let residentInputs = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: voiceProfile,
        )
        let residentModel = residentInputs.model

        let normalizedText = try await normalizerRef.speechText(
            text,
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

        let audioData: Data
        do {
            audioData = try GeneratedAudioFileEncoder.encodedAudioData(
                samples: audio,
                sampleRate: residentModel.sampleRate,
                format: audioFormat,
                fileManager: dependencies.fileManager,
            )
        } catch let outputError as GeneratedAudioFileOutputError {
            throw outputError.workerError
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingGeneratedFile)
        let writeStartedAt = dependencies.now()
        let generatedFile: GeneratedFileSummary
        do {
            generatedFile = try generatedFileStore.createGeneratedFile(
                artifactID: artifactID,
                voiceProfile: voiceProfile,
                textProfile: textProfile,
                sourceFormat: nil,
                requestContext: requestContext,
                sampleRate: residentModel.sampleRate,
                audioFormat: audioFormat,
                audioData: audioData,
            )
            .summary
        } catch let storeError as GeneratedFileStoreError {
            throw storeError.workerError
        }
        await logRequestEvent(
            "generated_file_written",
            requestID: id,
            op: op,
            profileName: voiceProfile,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "path": .string(generatedFile.filePath),
                "duration_ms": .int(elapsedMS(since: writeStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
                "audio_format": .string(audioFormat.rawValue),
            ],
        )

        return SpeakSwiftly.GeneratedFile(generatedFile)
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
                    reference: .raw(
                        materialization: materialization,
                        refAudio: refAudio,
                    ),
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            case let .qwenPrepared(model, _, conditioning):
                qwenGenerationStream(
                    requestID: requestID,
                    model: model,
                    text: text,
                    reference: .prepared(conditioning),
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
                    reference: .raw(
                        materialization: materialization,
                        refAudio: refAudio,
                    ),
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
                    reference: .prepared(conditioning),
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
        }
    }
}
