import Foundation

// MARK: - System Profile Resources

extension ProfileStore {
    struct SystemProfileResourceSeedSummary: Equatable {
        var installedCount = 0
        var replacedCount = 0
        var skippedCurrentCount = 0
        var skippedUserConflictCount = 0

        var changedCount: Int {
            installedCount + replacedCount
        }
    }

    static func systemProfileResourceRootURL(from resourceRootURL: URL) -> URL {
        let standardizedURL = resourceRootURL.standardizedFileURL
        guard standardizedURL.lastPathComponent != profilesDirectoryName else {
            return standardizedURL
        }

        return standardizedURL.appendingPathComponent(profilesDirectoryName, isDirectory: true)
    }

    func seedSystemProfiles(from resourceProfileRootURL: URL) throws -> SystemProfileResourceSeedSummary {
        try ensureRootExists()

        let sourceStore = ProfileStore(rootURL: resourceProfileRootURL, fileManager: fileManager)
        let sourceDirectories = try fileManager.contentsOfDirectory(
            at: resourceProfileRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        return try withExclusiveStoreAccess(operation: "seeding bundled system voice profiles") {
            var summary = SystemProfileResourceSeedSummary()

            for sourceDirectoryURL in sourceDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard try sourceStore.isDirectory(sourceDirectoryURL),
                      fileManager.fileExists(atPath: sourceStore.manifestURL(for: sourceDirectoryURL).path)
                else {
                    continue
                }

                let manifest = try sourceStore.loadManifest(from: sourceDirectoryURL)
                guard manifest.author == .system else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Bundled system profile resource '\(sourceDirectoryURL.path)' declares author '\(manifest.author.rawValue)'. Bundled system profile resources must be created through SpeakSwiftlyTool's system-profile resource workflow so they persist as package-owned system profiles.",
                    )
                }

                let destinationURL = profileDirectoryURL(for: manifest.profileName)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    let existing = try loadProfile(named: manifest.profileName)
                    guard existing.manifest.author == .system else {
                        summary.skippedUserConflictCount += 1
                        continue
                    }

                    if existing.manifest.seed?.seedID == manifest.seed?.seedID,
                       existing.manifest.seed?.seedVersion == manifest.seed?.seedVersion {
                        summary.skippedCurrentCount += 1
                        continue
                    }

                    try fileManager.removeItem(at: destinationURL)
                    try fileManager.copyItem(at: sourceDirectoryURL, to: destinationURL)
                    summary.replacedCount += 1
                } else {
                    try fileManager.copyItem(at: sourceDirectoryURL, to: destinationURL)
                    summary.installedCount += 1
                }
            }

            return summary
        }
    }
}
