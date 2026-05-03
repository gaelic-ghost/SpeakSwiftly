import Foundation

// MARK: - ProfileStore Temporary Directories

extension ProfileStore {
    func temporaryProfileDirectoryURL(
        for profileName: String,
        purpose: String,
    ) -> URL {
        rootURL.appendingPathComponent(
            ".\(profileName).\(purpose)-\(UUID().uuidString)",
            isDirectory: true,
        )
    }

    func cleanupStagedProfileDirectories(for profileName: String) throws {
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
            )
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "SpeakSwiftly could not inspect the profile store at '\(rootURL.path)' for abandoned staged data before writing profile '\(profileName)'. \(error.localizedDescription)",
            )
        }

        for url in urls {
            guard
                (try? isDirectory(url)) == true,
                isStagedProfileDirectoryName(url.lastPathComponent, profileName: profileName)
            else {
                continue
            }

            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw WorkerError(
                    code: .filesystemError,
                    message: "SpeakSwiftly could not remove abandoned staged profile data at '\(url.path)' before writing profile '\(profileName)'. \(error.localizedDescription)",
                )
            }
        }
    }

    private func isStagedProfileDirectoryName(
        _ directoryName: String,
        profileName: String,
    ) -> Bool {
        directoryName.hasPrefix(".\(profileName).create-")
            || directoryName.hasPrefix(".\(profileName).stage-")
    }
}
