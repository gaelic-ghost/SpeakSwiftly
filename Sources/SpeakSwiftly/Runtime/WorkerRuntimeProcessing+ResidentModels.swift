import Foundation
import TextForSpeech

// MARK: - Worker Runtime Resident Models

extension SpeakSwiftly.Runtime {
    func preloadModelRepos(for speechBackend: SpeakSwiftly.SpeechBackend) -> [String] {
        switch speechBackend {
            case .qwen3, .chatterboxTurbo:
                [ModelFactory.residentModelRepo(for: speechBackend)]
            case .marvis:
                [ModelFactory.marvisResidentModelRepo]
        }
    }

    func shouldApplyResidentPreloadResult(
        token: UUID,
        backend: SpeakSwiftly.SpeechBackend,
    ) -> Bool {
        residentPreloadToken == token && speechBackend == backend
    }

    func performOrderedSpeechBackendSwitch(
        to requestedSpeechBackend: SpeakSwiftly.SpeechBackend,
    ) async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        invalidateQwenConditioningCache()
        speechBackend = requestedSpeechBackend
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
            case .ready, .warming, .unloaded:
                return currentStatusSnapshot()
            case let .failed(error):
                throw error
        }
    }

    func performOrderedModelReload() async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        invalidateQwenConditioningCache()
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
            case .ready, .warming, .unloaded:
                return currentStatusSnapshot()
            case let .failed(error):
                throw error
        }
    }

    func performOrderedModelUnload() async -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        residentPreloadToken = nil
        invalidateQwenConditioningCache()
        residentState = .unloaded
        await emitStatus(.residentModelsUnloaded)
        return currentStatusSnapshot()
    }

    func invalidateQwenConditioningCache() {
        qwenConditioningCache.removeAll(keepingCapacity: true)
    }

    func primaryResidentSampleRate(for models: ResidentSpeechModels) -> Int {
        switch models {
            case let .qwen3(model):
                model.sampleRate
            case let .chatterboxTurbo(model):
                model.sampleRate
            case let .marvis(models):
                models.conversationalA.sampleRate
        }
    }

    func residentQwenModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down.",
            )
        }

        switch residentState {
            case let .ready(.qwen3(model)):
                return model
            case .ready(.chatterboxTurbo):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Qwen model while the runtime is configured for the 'chatterbox_turbo' backend. This indicates a backend-routing bug.",
                )
            case .ready(.marvis):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Qwen model while the runtime is configured for the 'marvis' backend. This indicates a backend-routing bug.",
                )
            case .warming:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.",
                )
            case .unloaded:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready.",
                )
            case let .failed(error):
                throw error
        }
    }

    func residentChatterboxModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down.",
            )
        }

        switch residentState {
            case let .ready(.chatterboxTurbo(model)):
                return model
            case .ready(.qwen3):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Chatterbox Turbo model while the runtime is configured for the '\(speechBackend.rawValue)' backend. This indicates a backend-routing bug.",
                )
            case .ready(.marvis):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Chatterbox Turbo model while the runtime is configured for the 'marvis' backend. This indicates a backend-routing bug.",
                )
            case .warming:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.",
                )
            case .unloaded:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready.",
                )
            case let .failed(error):
                throw error
        }
    }

    func residentMarvisModelOrThrow(
        for vibe: SpeakSwiftly.Vibe,
    ) throws -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down.",
            )
        }

        switch residentState {
            case let .ready(.marvis(models)):
                return models.model(for: vibe)
            case .ready(.qwen3), .ready(.chatterboxTurbo):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Marvis model bundle while the runtime is configured for the '\(speechBackend.rawValue)' backend. This indicates a backend-routing bug.",
                )
            case .warming:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.",
                )
            case .unloaded:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready.",
                )
            case let .failed(error):
                throw error
        }
    }

    func marvisGenerationLane(for request: WorkerRequest) throws -> MarvisResidentVoice? {
        guard speechBackend == .marvis else { return nil }

        let profileName: String? = switch request {
            case .queueSpeech(
            id: _,
            text: _,
            profileName: let profileName,
            textProfileID: _,
            jobType: _,
            textContext: _,
            sourceFormat: _,
        ):
                profileName
            case .queueBatch(id: _, profileName: let profileName, items: _):
                profileName
            default:
                nil
        }

        guard let profileName else { return nil }

        let profile = try profileStore.loadProfile(named: profileName)
        return MarvisResidentVoice.forVibe(profile.manifest.vibe)
    }
}
