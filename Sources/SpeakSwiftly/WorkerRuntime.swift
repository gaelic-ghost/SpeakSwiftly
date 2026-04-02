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

    private struct ActiveRequest: Sendable {
        let token: UUID
        let id: String
        let task: Task<Void, Never>
    }

    private struct QueueEntry: Sendable, Equatable {
        let token = UUID()
        let request: WorkerRequest
    }

    private struct WorkerSuccessPayload: Sendable {
        let id: String
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?

        init(id: String, profileName: String? = nil, profilePath: String? = nil, profiles: [ProfileSummary]? = nil) {
            self.id = id
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
        }
    }

    private enum LogLevel: String, Encodable {
        case info
        case error
    }

    private enum LogValue: Encodable, Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            }
        }
    }

    private struct LogEvent: Encodable {
        let event: String
        let level: LogLevel
        let ts: String
        let requestID: String?
        let op: String?
        let profileName: String?
        let queueDepth: Int?
        let elapsedMS: Int?
        let details: [String: LogValue]?

        enum CodingKeys: String, CodingKey {
            case event
            case level
            case ts
            case requestID = "request_id"
            case op
            case profileName = "profile_name"
            case queueDepth = "queue_depth"
            case elapsedMS = "elapsed_ms"
            case details
        }
    }

    private let dependencies: WorkerDependencies
    private let encoder = JSONEncoder()
    private let logEncoder = JSONEncoder()
    private let profileStore: ProfileStore
    private let playbackController: AnyPlaybackController
    private let logTimestampFormatter = ISO8601DateFormatter()

    private var residentState: ResidentState = .warming
    private var queue = [QueueEntry]()
    private var activeRequest: ActiveRequest?
    private var isShuttingDown = false
    private var preloadTask: Task<Void, Never>?
    private var requestAcceptedAt = [String: Date]()

    init(
        dependencies: WorkerDependencies,
        profileStore: ProfileStore,
        playbackController: AnyPlaybackController
    ) {
        self.dependencies = dependencies
        self.profileStore = profileStore
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
        logEncoder.outputFormatting = [.sortedKeys]
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
            let preloadStartedAt = dependencies.now()
            await emitStatus(.warmingResidentModel)
            await logEvent(
                "resident_model_preload_started",
                details: [
                    "model_repo": .string(ModelFactory.residentModelRepo),
                    "profile_root": .string(profileStore.rootURL.path),
                ]
            )

            do {
                try profileStore.ensureRootExists()
                let model = try await dependencies.loadResidentModel()
                residentState = .ready(model)
                await emitStatus(.residentModelReady)
                await logEvent(
                    "resident_model_preload_ready",
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
                try await startNextRequestIfPossible()
            } catch is CancellationError {
                guard !isShuttingDown else { return }

                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload was cancelled before \(ModelFactory.residentModelRepo) finished loading."
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch let workerError as WorkerError {
                residentState = .failed(workerError)
                await logError(
                    "Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(workerError.message)",
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                        "failure_code": .string(workerError.code.rawValue),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch {
                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(error.localizedDescription)"
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
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

        if isShuttingDown {
            await emitFailure(
                id: request.id,
                error: WorkerError(
                    code: .workerShuttingDown,
                    message: "Request '\(request.id)' was rejected because the SpeakSwiftly worker is shutting down."
                )
            )
            return
        }

        if case .failed(let error) = residentState {
            await emitFailure(id: request.id, error: error)
            return
        }

        let entry = QueueEntry(request: request)
        requestAcceptedAt[request.id] = dependencies.now()
        await logRequestEvent(
            "request_accepted",
            requestID: request.id,
            op: request.opName,
            profileName: request.profileName,
            queueDepth: queue.count
        )
        queue.append(entry)
        if let queuedEvent = makeQueuedEvent(for: entry) {
            await emit(queuedEvent)
            await logRequestEvent(
                "request_queued",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: queue.count
            )
        }
        try? await startNextRequestIfPossible()
    }

    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeRequest {
            self.activeRequest = nil
            activeRequest.task.cancel()
            await emitFailure(id: activeRequest.id, error: cancellationError)
        }

        await failQueuedRequests(with: cancellationError)
        await playbackController.stop()
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(queue.count)])
    }

    // MARK: - Processing

    private func startNextRequestIfPossible() async throws {
        guard !isShuttingDown else { return }
        guard activeRequest == nil else { return }

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
        await emitStarted(for: entry.request)
        await logRequestEvent(
            "request_started",
            requestID: entry.request.id,
            op: entry.request.opName,
            profileName: entry.request.profileName,
            queueDepth: queue.count
        )

        let task = Task {
            await self.process(entry.request, token: entry.token)
        }
        activeRequest = ActiveRequest(token: entry.token, id: entry.request.id, task: task)
    }

    private func process(_ request: WorkerRequest, token: UUID) async {
        let result: Result<WorkerSuccessPayload, WorkerError>

        do {
            switch request {
            case .speakLive(let id, let text, let profileName):
                try await handleSpeakLive(id: id, text: text, profileName: profileName)
                result = .success(WorkerSuccessPayload(id: id))

            case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
                let storedProfile = try await handleCreateProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath
                )
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        profileName: storedProfile.manifest.profileName,
                        profilePath: storedProfile.directoryURL.path
                    )
                )

            case .listProfiles(let id):
                let listStartedAt = dependencies.now()
                let profiles = try profileStore.listProfiles()
                await logRequestEvent(
                    "profiles_listed",
                    requestID: id,
                    op: request.opName,
                    details: [
                        "profile_root": .string(profileStore.rootURL.path),
                        "count": .int(profiles.count),
                        "duration_ms": .int(elapsedMS(since: listStartedAt)),
                    ]
                )
                result = .success(WorkerSuccessPayload(id: id, profiles: profiles))

            case .removeProfile(let id, let profileName):
                await emitProgress(id: id, stage: .removingProfile)
                let removeStartedAt = dependencies.now()
                try profileStore.removeProfile(named: profileName)
                await logRequestEvent(
                    "profile_removed",
                    requestID: id,
                    op: request.opName,
                    profileName: profileName,
                    details: [
                        "path": .string(profileStore.profileDirectoryURL(for: profileName).path),
                        "duration_ms": .int(elapsedMS(since: removeStartedAt)),
                    ]
                )
                result = .success(WorkerSuccessPayload(id: id, profileName: profileName))
            }
        } catch is CancellationError {
            result = .failure(cancellationError(for: request.id))
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .internalError,
                    message: "Request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishActiveRequest(token: token, requestID: request.id, result: result)
    }

    private func handleSpeakLive(id: String, text: String, profileName: String) async throws {
        let residentModel = try residentModelOrThrow()
        let op = WorkerRequest.speakLive(id: id, text: text, profileName: profileName).opName

        await emitProgress(id: id, stage: .loadingProfile)
        let profileLoadStartedAt = dependencies.now()
        let profile = try profileStore.loadProfile(named: profileName)
        await logRequestEvent(
            "profile_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(profile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileLoadStartedAt)),
            ]
        )

        let refAudioLoadStartedAt = dependencies.now()
        let refAudio = try dependencies.loadAudioSamples(profile.referenceAudioURL, residentModel.sampleRate)
        await logRequestEvent(
            "reference_audio_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(profile.referenceAudioURL.path),
                "duration_ms": .int(elapsedMS(since: refAudioLoadStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
            ]
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentModel.generateSamplesStream(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: profile.manifest.sourceText,
            language: "English",
            streamingInterval: 0.32
        )

        let playbackSummary = try await playbackController.play(sampleRate: Double(residentModel.sampleRate), stream: stream) { event in
            switch event {
            case .firstChunk:
                await self.emitProgress(id: id, stage: .bufferingAudio)
                await self.logRequestEvent(
                    "playback_first_chunk",
                    requestID: id,
                    op: op,
                    profileName: profileName
                )
            case .prerollReady:
                await self.emitProgress(id: id, stage: .prerollReady)
                await self.logRequestEvent(
                    "playback_preroll_ready",
                    requestID: id,
                    op: op,
                    profileName: profileName
                )
            }
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .playbackFinished)
        var details: [String: LogValue] = [
            "chunk_count": .int(playbackSummary.chunkCount),
            "sample_count": .int(playbackSummary.sampleCount),
            "preroll_chunk_count": .int(playbackSummary.prerollChunkCount),
        ]
        if let timeToFirstChunkMS = playbackSummary.timeToFirstChunkMS {
            details["time_to_first_chunk_ms"] = .int(timeToFirstChunkMS)
        }
        if let timeToPrerollReadyMS = playbackSummary.timeToPrerollReadyMS {
            details["time_to_preroll_ready_ms"] = .int(timeToPrerollReadyMS)
        }
        if let timeFromPrerollReadyToDrainMS = playbackSummary.timeFromPrerollReadyToDrainMS {
            details["time_from_preroll_ready_to_drain_ms"] = .int(timeFromPrerollReadyToDrainMS)
        }
        await logRequestEvent(
            "playback_finished",
            requestID: id,
            op: op,
            profileName: profileName,
            details: details
        )
    }

    private func handleCreateProfile(
        id: String,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createProfile(
            id: id,
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath
        ).opName
        try profileStore.validateProfileName(profileName)
        await emitProgress(id: id, stage: .loadingProfileModel)
        let modelLoadStartedAt = dependencies.now()
        let profileModel = try await dependencies.loadProfileModel()
        await logRequestEvent(
            "profile_model_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "model_repo": .string(ModelFactory.profileModelRepo),
                "duration_ms": .int(elapsedMS(since: modelLoadStartedAt)),
            ]
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let generationStartedAt = dependencies.now()
        let audio = try await profileModel.generate(
            text: text,
            voice: voiceDescription,
            refAudio: nil,
            refText: nil,
            language: "English"
        )
        await logRequestEvent(
            "profile_audio_generated",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ]
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        try dependencies.writeWAV(audio, profileModel.sampleRate, tempWavURL)
        let canonicalAudioData = try Data(contentsOf: tempWavURL)
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let storedProfile = try profileStore.createProfile(
            profileName: profileName,
            modelRepo: ModelFactory.profileModelRepo,
            voiceDescription: voiceDescription,
            sourceText: text,
            sampleRate: profileModel.sampleRate,
            canonicalAudioData: canonicalAudioData
        )
        await logRequestEvent(
            "profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ]
        )

        if let outputPath {
            await emitProgress(id: id, stage: .exportingProfileAudio)
            let exportStartedAt = dependencies.now()
            try profileStore.exportCanonicalAudio(for: storedProfile, to: outputPath)
            await logRequestEvent(
                "profile_exported",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "path": .string(profileStore.resolveOutputURL(outputPath).path),
                    "duration_ms": .int(elapsedMS(since: exportStartedAt)),
                ]
            )
        }

        return storedProfile
    }

    private func residentModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down."
            )
        }

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

    private func finishActiveRequest(token: UUID, requestID: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard activeRequest?.token == token else { return }

        activeRequest = nil
        defer { requestAcceptedAt.removeValue(forKey: requestID) }

        switch result {
        case .success(let payload):
            await logRequestEvent(
                "request_succeeded",
                requestID: payload.id,
                op: nil,
                profileName: payload.profileName
            )
            await emitSuccess(
                id: payload.id,
                profileName: payload.profileName,
                profilePath: payload.profilePath,
                profiles: payload.profiles
            )

        case .failure(let error):
            await logError(error.message, requestID: requestID, details: ["failure_code": .string(error.code.rawValue)])
            await emitFailure(id: requestID, error: error)
        }

        guard !isShuttingDown else { return }
        try? await startNextRequestIfPossible()
    }

    private func cancellationError(for id: String) -> WorkerError {
        if isShuttingDown {
            return WorkerError(
                code: .requestCancelled,
                message: "Request '\(id)' was cancelled because the SpeakSwiftly worker is shutting down."
            )
        }

        return WorkerError(
            code: .requestCancelled,
            message: "Request '\(id)' was cancelled before it could complete."
        )
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
            guard activeRequest != nil else { return nil }
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

    private func logError(
        _ message: String,
        requestID: String? = nil,
        op: String? = nil,
        profileName: String? = nil,
        details: [String: LogValue]? = nil
    ) async {
        var mergedDetails = details ?? [:]
        mergedDetails["message"] = .string(message)
        await logEvent(
            "worker_error",
            level: .error,
            requestID: requestID,
            op: op,
            profileName: profileName,
            elapsedMS: requestID.flatMap(elapsedMS(for:)),
            details: mergedDetails
        )
    }

    private func logRequestEvent(
        _ event: String,
        requestID: String,
        op: String?,
        profileName: String? = nil,
        queueDepth: Int? = nil,
        details: [String: LogValue]? = nil
    ) async {
        await logEvent(
            event,
            requestID: requestID,
            op: op,
            profileName: profileName,
            queueDepth: queueDepth,
            elapsedMS: elapsedMS(for: requestID),
            details: details
        )
    }

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        requestID: String? = nil,
        op: String? = nil,
        profileName: String? = nil,
        queueDepth: Int? = nil,
        elapsedMS: Int? = nil,
        details: [String: LogValue]? = nil
    ) async {
        let logEvent = LogEvent(
            event: event,
            level: level,
            ts: logTimestampFormatter.string(from: dependencies.now()),
            requestID: requestID,
            op: op,
            profileName: profileName,
            queueDepth: queueDepth,
            elapsedMS: elapsedMS,
            details: details
        )

        do {
            let data = try logEncoder.encode(logEvent)
            dependencies.writeStderr(String(decoding: data, as: UTF8.self))
        } catch {
            dependencies.writeStderr(
                #"{"event":"worker_error","level":"error","ts":"\#(logTimestampFormatter.string(from: dependencies.now()))","details":{"message":"SpeakSwiftly could not encode a stderr log event.","error":"\#(error.localizedDescription)"}}"#
            )
        }
    }

    private func elapsedMS(for requestID: String) -> Int? {
        guard let startedAt = requestAcceptedAt[requestID] else { return nil }
        return elapsedMS(since: startedAt)
    }

    private func elapsedMS(since startedAt: Date) -> Int {
        Int((dependencies.now().timeIntervalSince(startedAt) * 1_000).rounded())
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
