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

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func createFileJob(
        jobID: String,
        profileName: String,
        textProfileName: String?,
        speechBackend: SpeakSwiftly.SpeechBackend,
        item: SpeakSwiftly.GenerationJobItem,
        createdAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try createJob(
            jobID: jobID,
            jobKind: .file,
            profileName: profileName,
            textProfileName: textProfileName,
            speechBackend: speechBackend,
            items: [item],
            createdAt: createdAt,
        )
    }

    func createBatchJob(
        jobID: String,
        profileName: String,
        textProfileName: String?,
        speechBackend: SpeakSwiftly.SpeechBackend,
        items: [SpeakSwiftly.GenerationJobItem],
        createdAt: Date,
    ) throws -> SpeakSwiftly.GenerationJob {
        try createJob(
            jobID: jobID,
            jobKind: .batch,
            profileName: profileName,
            textProfileName: textProfileName,
            speechBackend: speechBackend,
            items: items,
            createdAt: createdAt,
        )
    }

    func loadGenerationJob(id jobID: String) throws -> SpeakSwiftly.GenerationJob {
        try ensureRootExists()
        let directoryURL = generationJobDirectoryURL(for: jobID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .generationJobNotFound,
                message: "Generation job '\(jobID)' was not found in the SpeakSwiftly generation-job store.",
            )
        }

        do {
            let data = try Data(contentsOf: manifestURL(for: directoryURL))
            return try decoder.decode(SpeakSwiftly.GenerationJob.self, from: data)
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Generation job '\(jobID)' exists, but its metadata could not be read. \(error.localizedDescription)",
            )
        }
    }

    func listGenerationJobs() throws -> [SpeakSwiftly.GenerationJob] {
        try ensureRootExists()

        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        let jobs = try urls.map { directoryURL in
            do {
                let data = try Data(contentsOf: manifestURL(for: directoryURL))
                return try decoder.decode(SpeakSwiftly.GenerationJob.self, from: data)
            } catch {
                throw WorkerError(
                    code: .filesystemError,
                    message: "SpeakSwiftly could not list generation jobs because the manifest in '\(directoryURL.path)' is unreadable or corrupt. \(error.localizedDescription)",
                )
            }
        }

        return jobs.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.jobID < $1.jobID
            }
            return $0.createdAt < $1.createdAt
        }
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
                profileName: job.profileName,
                textProfileName: job.textProfileName,
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
                profileName: job.profileName,
                textProfileName: job.textProfileName,
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
                profileName: job.profileName,
                textProfileName: job.textProfileName,
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
                profileName: job.profileName,
                textProfileName: job.textProfileName,
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

    func generationJobDirectoryURL(for jobID: String) -> URL {
        rootURL.appendingPathComponent(encodedDirectoryName(for: jobID), isDirectory: true)
    }

    func manifestURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    private func createJob(
        jobID: String,
        jobKind: SpeakSwiftly.GenerationJobKind,
        profileName: String,
        textProfileName: String?,
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
            profileName: profileName,
            textProfileName: textProfileName,
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

    private func updateGenerationJob(
        id jobID: String,
        mutate: (SpeakSwiftly.GenerationJob) throws -> SpeakSwiftly.GenerationJob,
    ) throws -> SpeakSwiftly.GenerationJob {
        let directoryURL = generationJobDirectoryURL(for: jobID)
        let job = try loadGenerationJob(id: jobID)
        let updated = try mutate(job)

        do {
            try write(updated, to: directoryURL)
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Generation job '\(jobID)' could not be updated on disk. \(error.localizedDescription)",
            )
        }

        return updated
    }

    private func write(_ job: SpeakSwiftly.GenerationJob, to directoryURL: URL) throws {
        let data = try encoder.encode(job)
        try data.write(to: manifestURL(for: directoryURL), options: .atomic)
    }

    private func encodedDirectoryName(for jobID: String) -> String {
        jobID.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
