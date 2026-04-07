import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
import TextForSpeech

// MARK: - Generated File Logic

extension SpeakSwiftly.Runtime {
    func handleQueueSpeechFileGeneration(
        id: String,
        op: String,
        text: String,
        profileName: String,
        textProfileName: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async throws -> SpeakSwiftly.GeneratedFile {
        let (residentModel, _, materialization, refAudio) = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: profileName
        )

        let textProfile = await normalizerRef.effectiveProfile(named: textProfileName)
        let normalizedText = if let sourceFormat {
            TextForSpeech.normalizeSource(
                text,
                as: sourceFormat,
                context: textContext,
                profile: textProfile
            )
        } else {
            TextForSpeech.normalizeText(
                text,
                context: textContext,
                profile: textProfile
            )
        }

        await emitProgress(id: id, stage: .generatingFileAudio)
        let generationStartedAt = dependencies.now()
        let stream = residentGenerationStream(
            model: residentModel,
            text: normalizedText,
            materialization: materialization,
            refAudio: refAudio,
            generationParameters: GenerationPolicy.residentParameters(for: normalizedText),
            streamingInterval: PlaybackConfiguration.residentStreamingInterval
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
            profileName: profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager.temporaryDirectory
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
            artifactID: id,
            profileName: profileName,
            textProfileName: textProfileName,
            sampleRate: residentModel.sampleRate,
            audioData: audioData
        )
        await logRequestEvent(
            "generated_file_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "path": .string(generatedFile.audioURL.path),
                "duration_ms": .int(elapsedMS(since: writeStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
            ]
        )

        return generatedFile.summary
    }

    func loadResidentSpeechInputs(
        requestID id: String,
        op: String,
        profileName: String
    ) async throws -> (
        model: AnySpeechModel,
        profile: StoredProfile,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?
    ) {
        let residentModel = try residentModelOrThrow()

        await emitProgress(id: id, stage: .loadingProfile)
        let profileLoadStartedAt = dependencies.now()
        let profile = try profileStore.loadProfile(named: profileName)
        let materialization = try profile.materialization(for: speechBackend)
        await logRequestEvent(
            "profile_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "path": .string(profile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileLoadStartedAt)),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )

        let refAudioLoadStartedAt = dependencies.now()
        let refAudio = try dependencies.loadAudioSamples(materialization.referenceAudioURL, residentModel.sampleRate)
        await logRequestEvent(
            "reference_audio_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "path": .string(materialization.referenceAudioURL.path),
                "duration_ms": .int(elapsedMS(since: refAudioLoadStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        return (residentModel, profile, materialization, refAudio)
    }

    func residentGenerationStream(
        model: AnySpeechModel,
        text: String,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        switch speechBackend {
        case .qwen3:
            qwenGenerationStream(
                model: model,
                text: text,
                materialization: materialization,
                refAudio: refAudio,
                generationParameters: generationParameters,
                streamingInterval: streamingInterval
            )
        case .marvis:
            marvisGenerationStream(
                model: model,
                text: text,
                materialization: materialization,
                refAudio: refAudio,
                generationParameters: generationParameters,
                streamingInterval: streamingInterval
            )
        }
    }
}
