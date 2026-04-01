import Foundation

// MARK: - Worker Runtime

actor WorkerRuntime {
    private enum Environment {
        static let profileRootOverride = "SPEAKSWIFTLY_PROFILE_ROOT"
    }

    private enum ResidentState: Sendable {
        case warming
        case ready(AnySpeechModel)
        case failed(WorkerError)
    }

    private struct QueueEntry: Sendable, Equatable {
        let token = UUID()
        let request: WorkerRequest
    }

    private let dependencies: WorkerDependencies
    private let encoder = JSONEncoder()
    private let profileStore: ProfileStore
    private let playbackController: AnyPlaybackController

    private var residentState: ResidentState = .warming
    private var queue = [QueueEntry]()
    private var activeRequestID: String?
    private var preloadTask: Task<Void, Never>?

    init(
        dependencies: WorkerDependencies,
        profileStore: ProfileStore,
        playbackController: AnyPlaybackController
    ) {
        self.dependencies = dependencies
        self.profileStore = profileStore
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
    }

    static func live() async -> WorkerRuntime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride]
            ),
            fileManager: dependencies.fileManager
        )
        let playbackController = await dependencies.makePlaybackController()

        return WorkerRuntime(
            dependencies: dependencies,
            profileStore: profileStore,
            playbackController: playbackController
        )
    }

    func start() {
        preloadTask = Task {
            await emitStatus(.warmingResidentModel)

            do {
                try profileStore.ensureRootExists()
                let model = try await dependencies.loadResidentModel()
                residentState = .ready(model)
                await emitStatus(.residentModelReady)
                try await startNextRequestIfPossible()
            } catch let workerError as WorkerError {
                residentState = .failed(workerError)
                await logError("Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(workerError.message)")
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch {
                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(error.localizedDescription)"
                )
                residentState = .failed(workerError)
                await logError(workerError.message)
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            }
        }
    }

    func accept(line: String) async {
        let request: WorkerRequest

        do {
            request = try WorkerRequest.decode(from: line)
        } catch let workerError as WorkerError {
            let id = bestEffortID(from: line)
            await emitFailure(id: id, error: workerError)
            return
        } catch {
            await emitFailure(
                id: bestEffortID(from: line),
                error: WorkerError(code: .internalError, message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)")
            )
            return
        }

        if case .failed(let error) = residentState {
            await emitFailure(id: request.id, error: error)
            return
        }

        let entry = QueueEntry(request: request)
        queue.append(entry)
        if let queuedEvent = makeQueuedEvent(for: entry) {
            await emit(queuedEvent)
        }
        try? await startNextRequestIfPossible()
    }

    func shutdown() async {
        preloadTask?.cancel()
        await playbackController.stop()
    }

    // MARK: - Processing

    private func startNextRequestIfPossible() async throws {
        guard activeRequestID == nil else { return }

        switch residentState {
        case .warming:
            return
        case .failed(let error):
            await failQueuedRequests(with: error)
            return
        case .ready:
            break
        }

        guard let index = nextQueueIndex() else { return }

        let entry = queue.remove(at: index)
        activeRequestID = entry.request.id
        await emitStarted(for: entry.request)

        Task {
            await self.process(entry.request)
        }
    }

    private func process(_ request: WorkerRequest) async {
        defer {
            activeRequestID = nil
            Task { try? await startNextRequestIfPossible() }
        }

        do {
            switch request {
            case .speakLive(let id, let text, let profileName):
                try await handleSpeakLive(id: id, text: text, profileName: profileName)
                await emitSuccess(id: id, profileName: nil, profilePath: nil, profiles: nil)

            case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
                let storedProfile = try await handleCreateProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath
                )
                await emitSuccess(id: id, profileName: storedProfile.manifest.profileName, profilePath: storedProfile.directoryURL.path, profiles: nil)

            case .listProfiles(let id):
                let profiles = try profileStore.listProfiles()
                await emitSuccess(id: id, profileName: nil, profilePath: nil, profiles: profiles)

            case .removeProfile(let id, let profileName):
                await emitProgress(id: id, stage: .removingProfile)
                try profileStore.removeProfile(named: profileName)
                await emitSuccess(id: id, profileName: profileName, profilePath: nil, profiles: nil)
            }
        } catch let workerError as WorkerError {
            await logError(workerError.message)
            await emitFailure(id: request.id, error: workerError)
        } catch {
            let workerError = WorkerError(
                code: .internalError,
                message: "Request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)"
            )
            await logError(workerError.message)
            await emitFailure(id: request.id, error: workerError)
        }
    }

    private func handleSpeakLive(id: String, text: String, profileName: String) async throws {
        let residentModel = try residentModelOrThrow()

        await emitProgress(id: id, stage: .loadingProfile)
        let profile = try profileStore.loadProfile(named: profileName)
        let refAudio = try dependencies.loadAudioSamples(profile.referenceAudioURL, residentModel.sampleRate)

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentModel.generateSamplesStream(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: profile.manifest.sourceText,
            language: "English",
            streamingInterval: 0.32
        )

        try await playbackController.play(sampleRate: Double(residentModel.sampleRate), stream: stream) {
            await self.emitProgress(id: id, stage: .bufferingAudio)
        }

        await emitProgress(id: id, stage: .playbackFinished)
    }

    private func handleCreateProfile(
        id: String,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?
    ) async throws -> StoredProfile {
        try profileStore.validateProfileName(profileName)
        await emitProgress(id: id, stage: .loadingProfileModel)
        let profileModel = try await dependencies.loadProfileModel()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let audio = try await profileModel.generate(
            text: text,
            voice: voiceDescription,
            refAudio: nil,
            refText: nil,
            language: "English"
        )

        let tempDirectory = dependencies.fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        try dependencies.writeWAV(audio, profileModel.sampleRate, tempWavURL)
        let canonicalAudioData = try Data(contentsOf: tempWavURL)

        await emitProgress(id: id, stage: .writingProfileAssets)
        let storedProfile = try profileStore.createProfile(
            profileName: profileName,
            modelRepo: ModelFactory.profileModelRepo,
            voiceDescription: voiceDescription,
            sourceText: text,
            sampleRate: profileModel.sampleRate,
            canonicalAudioData: canonicalAudioData
        )

        if let outputPath {
            await emitProgress(id: id, stage: .exportingProfileAudio)
            try profileStore.exportCanonicalAudio(for: storedProfile, to: outputPath)
        }

        return storedProfile
    }

    private func residentModelOrThrow() throws -> AnySpeechModel {
        switch residentState {
        case .ready(let model):
            return model
        case .warming:
            throw WorkerError(code: .modelLoading, message: "The resident \(ModelFactory.residentModelRepo) model is still loading.")
        case .failed(let error):
            throw error
        }
    }

    private func nextQueueIndex() -> Int? {
        if let playbackIndex = queue.firstIndex(where: { $0.request.isPlayback }) {
            return playbackIndex
        }
        return queue.isEmpty ? nil : queue.startIndex
    }

    private func failQueuedRequests(with error: WorkerError) async {
        let queuedRequests = queue
        queue.removeAll()

        for entry in queuedRequests {
            await emitFailure(id: entry.request.id, error: error)
        }
    }

    // MARK: - Emission

    private func makeQueuedEvent(for entry: QueueEntry) -> WorkerQueuedEvent? {
        let reason: WorkerQueuedReason
        switch residentState {
        case .warming:
            reason = .waitingForResidentModel
        case .failed:
            return nil
        case .ready:
            guard activeRequestID != nil else { return nil }
            reason = .waitingForActiveRequest
        }

        let queuePosition = waitingQueuePosition(for: entry)
        return WorkerQueuedEvent(id: entry.request.id, reason: reason, queuePosition: queuePosition)
    }

    private func waitingQueuePosition(for entry: QueueEntry) -> Int {
        let orderedQueue = orderedWaitingQueue()

        guard let index = orderedQueue.firstIndex(of: entry) else {
            return 1
        }

        return index + 1
    }

    private func orderedWaitingQueue() -> [QueueEntry] {
        let playbackRequests = queue.filter(\.request.isPlayback)
        let nonPlaybackRequests = queue.filter { !$0.request.isPlayback }
        return playbackRequests + nonPlaybackRequests
    }

    private func emitStarted(for request: WorkerRequest) async {
        await emit(WorkerStartedEvent(id: request.id, op: request.opName))
    }

    private func emitProgress(id: String, stage: WorkerProgressStage) async {
        await emit(WorkerProgressEvent(id: id, stage: stage))
    }

    private func emitStatus(_ stage: WorkerStatusStage) async {
        await emit(WorkerStatusEvent(stage: stage))
    }

    private func emitSuccess(id: String, profileName: String?, profilePath: String?, profiles: [ProfileSummary]?) async {
        await emit(WorkerSuccessResponse(id: id, profileName: profileName, profilePath: profilePath, profiles: profiles))
    }

    private func emitFailure(id: String, error: WorkerError) async {
        await emit(WorkerFailureResponse(id: id, code: error.code, message: error.message))
    }

    private func emit<T: Encodable>(_ value: T) async {
        do {
            let data = try encoder.encode(value) + Data("\n".utf8)
            try dependencies.writeStdout(data)
        } catch {
            await logError("SpeakSwiftly could not write a JSONL event to stdout. \(error.localizedDescription)")
        }
    }

    private func logError(_ message: String) async {
        dependencies.writeStderr(message)
    }

    private func bestEffortID(from line: String) -> String {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty
        else {
            return "unknown"
        }

        return id
    }
}
