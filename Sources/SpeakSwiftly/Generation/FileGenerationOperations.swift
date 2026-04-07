import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
import TextForSpeech

// MARK: - Generated File Logic

extension SpeakSwiftly.Runtime {
    enum ResidentSpeechInputs {
        case qwen(
            model: AnySpeechModel,
            profile: StoredProfile,
            materialization: StoredProfileMaterialization,
            refAudio: MLXArray?
        )
        case marvis(
            model: AnySpeechModel,
            profile: StoredProfile,
            voice: MarvisResidentVoice
        )
    }

    func handleQueueSpeechFileGeneration(
        requestID id: String,
        op: String,
        artifactID: String,
        text: String,
        profileName: String,
        textProfileName: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async throws -> SpeakSwiftly.GeneratedFile {
        let residentInputs = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: profileName
        )
        let residentModel = residentInputs.model

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
            text: normalizedText,
            inputs: residentInputs,
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
            artifactID: artifactID,
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
    ) async throws -> ResidentSpeechInputs {
        await emitProgress(id: id, stage: .loadingProfile)
        let profileLoadStartedAt = dependencies.now()
        let profile = try profileStore.loadProfile(named: profileName)
        await logRequestEvent(
            "profile_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "profile_vibe": .string(profile.manifest.vibe.rawValue),
                "path": .string(profile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileLoadStartedAt)),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        switch speechBackend {
        case .qwen3:
            let residentModel = try residentQwenModelOrThrow()
            let materialization = try profile.qwenMaterialization()
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
            return .qwen(
                model: residentModel,
                profile: profile,
                materialization: materialization,
                refAudio: refAudio
            )

        case .marvis:
            let (residentModel, voice) = try residentMarvisModelOrThrow(for: profile.manifest.vibe)
            await logRequestEvent(
                "marvis_voice_selected",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "speech_backend": .string(speechBackend.rawValue),
                    "profile_vibe": .string(profile.manifest.vibe.rawValue),
                    "marvis_voice": .string(voice.rawValue),
                ]
            )
            return .marvis(model: residentModel, profile: profile, voice: voice)
        }
    }

    func residentGenerationStream(
        text: String,
        inputs: ResidentSpeechInputs,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        switch inputs {
        case .qwen(let model, _, let materialization, let refAudio):
            qwenGenerationStream(
                model: model,
                text: text,
                materialization: materialization,
                refAudio: refAudio,
                generationParameters: generationParameters,
                streamingInterval: streamingInterval
            )
        case .marvis(let model, _, let voice):
            marvisGenerationStream(
                model: model,
                text: text,
                voice: voice,
                generationParameters: generationParameters,
                streamingInterval: streamingInterval
            )
        }
    }
}

extension SpeakSwiftly.Runtime.ResidentSpeechInputs {
    var model: AnySpeechModel {
        switch self {
        case .qwen(let model, _, _, _), .marvis(let model, _, _):
            model
        }
    }
}
