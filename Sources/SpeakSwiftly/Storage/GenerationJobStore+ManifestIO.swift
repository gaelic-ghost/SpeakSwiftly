import Foundation

extension GenerationJobStore {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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

    func generationJobDirectoryURL(for jobID: String) -> URL {
        rootURL.appendingPathComponent(encodedDirectoryName(for: jobID), isDirectory: true)
    }

    func manifestURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    func updateGenerationJob(
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

    func write(_ job: SpeakSwiftly.GenerationJob, to directoryURL: URL) throws {
        let data = try encoder.encode(job)
        try data.write(to: manifestURL(for: directoryURL), options: .atomic)
    }

    func encodedDirectoryName(for jobID: String) -> String {
        jobID.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
