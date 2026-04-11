import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon
import MLXAudioTTS
import TextForSpeech

// MARK: - Generated File Logic

extension SpeakSwiftly.Runtime {
    enum ResidentSpeechInputs {
        case qwenRaw(
            model: AnySpeechModel,
            profile: StoredProfile,
            materialization: StoredProfileMaterialization,
            refAudio: MLXArray?
        )
        case qwenPrepared(
            model: AnySpeechModel,
            profile: StoredProfile,
            conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning
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

        let textProfileStyle = await normalizerRef.profiles.builtInStyle()
        let textProfile = if let textProfileName {
            await normalizerRef.profiles.stored(id: textProfileName) ?? .default
        } else {
            await normalizerRef.profiles.active() ?? .default
        }
        let normalizedText = if let sourceFormat {
            TextForSpeech.Normalize.source(
                text,
                as: sourceFormat,
                context: textContext,
                customProfile: textProfile,
                style: textProfileStyle
            )
        } else {
            TextForSpeech.Normalize.text(
                text,
                context: textContext,
                customProfile: textProfile,
                style: textProfileStyle
            )
        }

        await emitProgress(id: id, stage: .generatingFileAudio)
        let generationStartedAt = dependencies.now()
        let stream = residentGenerationStream(
            requestID: id,
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
        case .qwen3, .qwen3CustomVoice:
            let residentModel = try residentQwenModelOrThrow()
            switch qwenConditioningStrategy {
            case .legacyRaw:
                let materialization = try profile.qwenMaterialization(for: speechBackend)
                let refAudioLoadStartedAt = dependencies.now()
                let refAudio = try dependencies.loadAudioSamples(materialization.referenceAudioURL, residentModel.sampleRate)
                await logRequestEvent(
                    "reference_audio_loaded",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "speech_backend": .string(speechBackend.rawValue),
                        "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                        "path": .string(materialization.referenceAudioURL.path),
                        "duration_ms": .int(elapsedMS(since: refAudioLoadStartedAt)),
                        "sample_rate": .int(residentModel.sampleRate),
                    ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
                )
                try Task.checkCancellation()
                return .qwenRaw(
                    model: residentModel,
                    profile: profile,
                    materialization: materialization,
                    refAudio: refAudio
                )

            case .preparedConditioning:
                let conditioning = try await loadPreparedQwenConditioning(
                    requestID: id,
                    op: op,
                    profile: profile,
                    model: residentModel
                )
                return .qwenPrepared(
                    model: residentModel,
                    profile: profile,
                    conditioning: conditioning
                )
            }

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
        requestID: String,
        text: String,
        inputs: ResidentSpeechInputs,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        switch inputs {
        case .qwenRaw(let model, _, let materialization, let refAudio):
            qwenGenerationStream(
                requestID: requestID,
                model: model,
                text: text,
                materialization: materialization,
                refAudio: refAudio,
                generationParameters: generationParameters,
                streamingInterval: streamingInterval
            )
        case .qwenPrepared(let model, _, let conditioning):
            qwenGenerationStream(
                requestID: requestID,
                model: model,
                text: text,
                conditioning: conditioning,
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

    func loadPreparedQwenConditioning(
        requestID id: String,
        op: String,
        profile: StoredProfile,
        model: AnySpeechModel
    ) async throws -> Qwen3TTSModel.Qwen3TTSReferenceConditioning {
        if let storedArtifact = profile.qwenConditioningArtifact(for: speechBackend) {
            let cacheKey = qwenConditioningCacheKey(
                for: profile.manifest.profileName,
                artifact: storedArtifact
            )
            if let cachedConditioning = qwenConditioningCache[cacheKey] {
                await logRequestEvent(
                    "qwen_reference_conditioning_cache_hit",
                    requestID: id,
                    op: op,
                    profileName: profile.manifest.profileName,
                    details: [
                        "speech_backend": .string(speechBackend.rawValue),
                        "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                        "artifact_path": .string(storedArtifact.artifactURL.path),
                    ]
                )
                return cachedConditioning
            }

            let artifactLoadStartedAt = dependencies.now()
            let loadedConditioning = try profileStore.loadQwenConditioningArtifact(storedArtifact)
            qwenConditioningCache[cacheKey] = loadedConditioning
            await logRequestEvent(
                "qwen_reference_conditioning_loaded",
                requestID: id,
                op: op,
                profileName: profile.manifest.profileName,
                details: [
                    "speech_backend": .string(speechBackend.rawValue),
                    "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                    "artifact_path": .string(storedArtifact.artifactURL.path),
                    "duration_ms": .int(elapsedMS(since: artifactLoadStartedAt)),
                ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
            )
            return loadedConditioning
        }

        let materialization = try profile.qwenMaterialization(for: speechBackend)
        let refAudioLoadStartedAt = dependencies.now()
        let refAudio = try dependencies.loadAudioSamples(materialization.referenceAudioURL, model.sampleRate)
        guard let refAudio else {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profile.manifest.profileName)' uses the prepared Qwen conditioning path, but SpeakSwiftly could not load any reference audio samples from '\(materialization.referenceAudioURL.path)'. Recreate or reroll the profile to restore its canonical reference audio."
            )
        }
        await logRequestEvent(
            "reference_audio_loaded",
            requestID: id,
            op: op,
            profileName: profile.manifest.profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                "path": .string(materialization.referenceAudioURL.path),
                "duration_ms": .int(elapsedMS(since: refAudioLoadStartedAt)),
                "sample_rate": .int(model.sampleRate),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        let preparationStartedAt = dependencies.now()
        let preparedConditioning = try model.prepareQwenReferenceConditioning(
            refAudio: refAudio,
            refText: materialization.manifest.referenceText,
            language: "English"
        )
        await logRequestEvent(
            "qwen_reference_conditioning_prepared",
            requestID: id,
            op: op,
            profileName: profile.manifest.profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                "duration_ms": .int(elapsedMS(since: preparationStartedAt)),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        let persistenceStartedAt = dependencies.now()
        let updatedProfile = try profileStore.storeQwenConditioningArtifact(
            named: profile.manifest.profileName,
            backend: speechBackend,
            modelRepo: ModelFactory.residentModelRepo(for: speechBackend),
            conditioning: preparedConditioning
        )
        guard let storedArtifact = updatedProfile.qwenConditioningArtifact(for: speechBackend) else {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profile.manifest.profileName)' was updated after Qwen conditioning preparation, but SpeakSwiftly could not find the stored conditioning artifact for the '\(speechBackend.rawValue)' backend. This indicates a profile-store bug."
            )
        }

        let cacheKey = qwenConditioningCacheKey(
            for: updatedProfile.manifest.profileName,
            artifact: storedArtifact
        )
        qwenConditioningCache[cacheKey] = preparedConditioning
        await logRequestEvent(
            "qwen_reference_conditioning_persisted",
            requestID: id,
            op: op,
            profileName: updatedProfile.manifest.profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                "artifact_path": .string(storedArtifact.artifactURL.path),
                "duration_ms": .int(elapsedMS(since: persistenceStartedAt)),
            ]
        )

        return preparedConditioning
    }
}

extension SpeakSwiftly.Runtime.ResidentSpeechInputs {
    var model: AnySpeechModel {
        switch self {
        case .qwenRaw(let model, _, _, _), .qwenPrepared(let model, _, _), .marvis(let model, _, _):
            model
        }
    }
}

private extension SpeakSwiftly.Runtime {
    func qwenConditioningCacheKey(
        for profileName: String,
        artifact: StoredQwenConditioningArtifact
    ) -> QwenConditioningCacheKey {
        QwenConditioningCacheKey(
            profileName: profileName,
            backend: artifact.manifest.backend,
            modelRepo: artifact.manifest.modelRepo,
            artifactVersion: artifact.manifest.artifactVersion,
            artifactFile: artifact.manifest.artifactFile
        )
    }
}
