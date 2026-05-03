import Darwin
import Foundation

// MARK: - ProfileStore Coordination

extension ProfileStore {
    private static let coordinationLockFileName = ".profile-store.lock"
    private static let coordinationLockRetryIntervalMicroseconds: useconds_t = 20000
    private static let coordinationLockTimeoutMicroseconds: useconds_t = 10_000_000

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

        try acquireExclusiveLock(
            descriptor: descriptor,
            lockPath: lockPath,
            operation: operation,
        )

        defer {
            _ = flock(descriptor, LOCK_UN)
        }

        return try body()
    }

    private func acquireExclusiveLock(
        descriptor: Int32,
        lockPath: String,
        operation: String,
    ) throws {
        var waitedMicroseconds: useconds_t = 0

        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return
            }

            let lockErrno = errno
            guard lockErrno == EWOULDBLOCK || lockErrno == EAGAIN else {
                let lockError = String(cString: strerror(lockErrno))
                throw WorkerError(
                    code: .filesystemError,
                    message: "SpeakSwiftly could not acquire the profile-store coordination lock at '\(lockPath)' before \(operation). \(lockError)",
                )
            }
            guard waitedMicroseconds < Self.coordinationLockTimeoutMicroseconds else {
                let timeoutSeconds = Double(Self.coordinationLockTimeoutMicroseconds) / 1_000_000
                throw WorkerError(
                    code: .filesystemError,
                    message: "SpeakSwiftly waited \(timeoutSeconds) seconds for the profile-store coordination lock at '\(lockPath)' before \(operation), but another local process still appears to be writing the profile store. If this persists, check for a stuck SpeakSwiftly worker or remove only the lock file after confirming no SpeakSwiftly process is using this profile root.",
                )
            }

            usleep(Self.coordinationLockRetryIntervalMicroseconds)
            waitedMicroseconds += Self.coordinationLockRetryIntervalMicroseconds
        }
    }
}
