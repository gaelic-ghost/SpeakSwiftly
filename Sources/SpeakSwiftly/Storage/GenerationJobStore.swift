import Foundation

// MARK: - Generation Job Store

struct GenerationJobStore {
    static let directoryName = "generation-jobs"
    static let manifestFileName = "generation-job.json"

    let rootURL: URL
    let fileManager: FileManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = GenerationJobStore.makeEncoder(),
        decoder: JSONDecoder = GenerationJobStore.makeDecoder(),
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func createFileJob(
        jobID: String,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        speechBackend: SpeakSwiftly.SpeechBackend,
        item: SpeakSwiftly.GenerationJobItem,
        createdAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try createJob(
            jobID: jobID,
            jobKind: .file,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            speechBackend: speechBackend,
            items: [item],
            createdAt: createdAt,
        )
    }

    func createBatchJob(
        jobID: String,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        speechBackend: SpeakSwiftly.SpeechBackend,
        items: [SpeakSwiftly.GenerationJobItem],
        createdAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try createJob(
            jobID: jobID,
            jobKind: .batch,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            speechBackend: speechBackend,
            items: items,
            createdAt: createdAt,
        )
    }

    func markRunning(
        id jobID: String,
        speechBackend: SpeakSwiftly.SpeechBackend,
        startedAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try updateGenerationJob(id: jobID) { job in
            SpeakSwiftly.GenerationJob(
                jobID: job.jobID,
                jobKind: job.jobKind,
                createdAt: job.createdAt,
                updatedAt: startedAt,
                voiceProfile: job.voiceProfile,
                textProfile: job.textProfile,
                speechBackend: speechBackend,
                state: .running,
                items: job.items,
                artifacts: job.artifacts,
                failure: nil,
                startedAt: job.startedAt ?? startedAt,
                completedAt: nil,
                failedAt: nil,
                expiresAt: job.expiresAt,
                retentionPolicy: job.retentionPolicy,
            )
        }
    }

    func markRunning(id jobID: String, startedAt: Date) throws -> SpeakSwiftly.GenerationJob {
        let current = try loadGenerationJob(id: jobID)
        return try markRunning(
            id: jobID,
            speechBackend: current.speechBackend,
            startedAt: startedAt,
        )
    }

    func markCompleted(
        id jobID: String,
        artifacts: [SpeakSwiftly.GenerationArtifact],
        completedAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try updateGenerationJob(id: jobID) { job in
            SpeakSwiftly.GenerationJob(
                jobID: job.jobID,
                jobKind: job.jobKind,
                createdAt: job.createdAt,
                updatedAt: completedAt,
                voiceProfile: job.voiceProfile,
                textProfile: job.textProfile,
                speechBackend: job.speechBackend,
                state: .completed,
                items: job.items,
                artifacts: artifacts,
                failure: nil,
                startedAt: job.startedAt,
                completedAt: completedAt,
                failedAt: nil,
                expiresAt: job.expiresAt,
                retentionPolicy: job.retentionPolicy,
            )
        }
    }

    func markFailed(
        id jobID: String,
        error: WorkerError,
        failedAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try updateGenerationJob(id: jobID) { job in
            SpeakSwiftly.GenerationJob(
                jobID: job.jobID,
                jobKind: job.jobKind,
                createdAt: job.createdAt,
                updatedAt: failedAt,
                voiceProfile: job.voiceProfile,
                textProfile: job.textProfile,
                speechBackend: job.speechBackend,
                state: .failed,
                items: job.items,
                artifacts: job.artifacts,
                failure: .init(code: error.code.rawValue, message: error.message),
                startedAt: job.startedAt,
                completedAt: nil,
                failedAt: failedAt,
                expiresAt: job.expiresAt,
                retentionPolicy: job.retentionPolicy,
            )
        }
    }

    func markExpired(
        id jobID: String,
        expiredAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try updateGenerationJob(id: jobID) { job in
            guard job.state != .queued, job.state != .running else {
                throw WorkerError(
                    code: .generationJobNotExpirable,
                    message: "Generation job '\(jobID)' is still \(job.state.rawValue) and cannot be expired until it has either completed or failed.",
                )
            }

            if job.state == .expired {
                return job
            }

            return SpeakSwiftly.GenerationJob(
                jobID: job.jobID,
                jobKind: job.jobKind,
                createdAt: job.createdAt,
                updatedAt: expiredAt,
                voiceProfile: job.voiceProfile,
                textProfile: job.textProfile,
                speechBackend: job.speechBackend,
                state: .expired,
                items: job.items,
                artifacts: job.artifacts,
                failure: job.failure,
                startedAt: job.startedAt,
                completedAt: job.completedAt,
                failedAt: job.failedAt,
                expiresAt: expiredAt,
                retentionPolicy: job.retentionPolicy,
            )
        }
    }

    private func createJob(
        jobID: String,
        jobKind: SpeakSwiftly.GenerationJobKind,
        voiceProfile: String,
        textProfile: SpeakSwiftly.TextProfileID?,
        speechBackend: SpeakSwiftly.SpeechBackend,
        items: [SpeakSwiftly.GenerationJobItem],
        createdAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try ensureRootExists()

        let directoryURL = generationJobDirectoryURL(for: jobID)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .generationJobAlreadyExists,
                message: "Generation job '\(jobID)' already exists in the SpeakSwiftly generation-job store and cannot be overwritten.",
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let job = SpeakSwiftly.GenerationJob(
            jobID: jobID,
            jobKind: jobKind,
            createdAt: createdAt,
            updatedAt: createdAt,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            speechBackend: speechBackend,
            state: .queued,
            items: items,
            artifacts: [],
            failure: nil,
            startedAt: nil,
            completedAt: nil,
            failedAt: nil,
            expiresAt: nil,
            retentionPolicy: .manual,
        )

        do {
            try write(job, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw WorkerError(
                code: .filesystemError,
                message: "Generation job '\(jobID)' could not be written to disk. \(error.localizedDescription)",
            )
        }

        return job
    }
}
