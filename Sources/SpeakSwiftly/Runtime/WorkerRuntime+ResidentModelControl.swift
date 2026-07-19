import Foundation

// MARK: - Worker Runtime Resident Models

extension SpeakSwiftly.Runtime {
    func preloadModelRepos(for speechBackend: SpeakSwiftly.SpeechBackend) -> [String] {
        [ModelFactory.residentModelRepo(for: speechBackend)]
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
}
