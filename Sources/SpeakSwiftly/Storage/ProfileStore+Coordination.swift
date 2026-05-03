import Darwin
import Foundation

// MARK: - ProfileStore Coordination

extension ProfileStore {
    private static let coordinationLockFileName = ".profile-store.lock"

    private var coordinationLockURL: URL {
        rootURL.appendingPathComponent(Self.coordinationLockFileName, isDirectory: false)
    }

    func withExclusiveStoreAccess<T>(
        operation: String,
        _ body: () throws -> T,
    ) throws -> T {
        try ensureRootExists()

        let lockPath = coordinationLockURL.path
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkerError(
                code: .filesystemError,
                message: "SpeakSwiftly could not open the profile-store coordination lock at '\(lockPath)' before \(operation). \(String(cString: strerror(errno)))",
            )
        }

        defer {
            _ = close(descriptor)
        }

        guard flock(descriptor, LOCK_EX) == 0 else {
            let lockError = String(cString: strerror(errno))
            throw WorkerError(
                code: .filesystemError,
                message: "SpeakSwiftly could not acquire the profile-store coordination lock at '\(lockPath)' before \(operation). \(lockError)",
            )
        }

        defer {
            _ = flock(descriptor, LOCK_UN)
        }

        return try body()
    }
}
