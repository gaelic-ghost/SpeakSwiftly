import Foundation
import TextForSpeech

extension SpeakSwiftly.Runtime {
    private static func makeDefaultNormalizer(
        persistenceURL: URL,
        dependencies: WorkerDependencies,
    ) -> SpeakSwiftly.Normalizer {
        do {
            return try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
        } catch {
            let archiveURL = quarantinedTextProfileArchiveURL(for: persistenceURL)

            if dependencies.fileManager.fileExists(atPath: persistenceURL.path) {
                do {
                    try dependencies.fileManager.moveItem(at: persistenceURL, to: archiveURL)
                    dependencies.writeStderr(
                        "SpeakSwiftly could not load persisted text profiles from '\(persistenceURL.path)'. The unreadable archive was moved to '\(archiveURL.path)', and SpeakSwiftly will continue with a fresh text-profile state. \(error.localizedDescription)\n",
                    )

                    return try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
                } catch {
                    dependencies.writeStderr(
                        "SpeakSwiftly could not recover the unreadable text-profile archive at '\(persistenceURL.path)'. SpeakSwiftly will continue without that archive. \(error.localizedDescription)\n",
                    )
                }
            } else {
                dependencies.writeStderr(
                    "SpeakSwiftly could not initialize text-profile persistence at '\(persistenceURL.path)'. SpeakSwiftly will continue without that archive. \(error.localizedDescription)\n",
                )
            }

            let recoveryURL = persistenceURL
                .deletingLastPathComponent()
                .appending(path: "text-profiles.recovery.\(UUID().uuidString).json")

            do {
                return try SpeakSwiftly.Normalizer(persistenceURL: recoveryURL)
            } catch {
                fatalError(
                    "SpeakSwiftly could not create a recovery text normalizer at '\(recoveryURL.path)' after the primary archive failed to load. SpeakSwiftly cannot continue without a writable text-profile archive. \(error.localizedDescription)",
                )
            }
        }
    }

    private static func quarantinedTextProfileArchiveURL(for persistenceURL: URL) -> URL {
        persistenceURL
            .deletingPathExtension()
            .appendingPathExtension("invalid-\(Int(Date().timeIntervalSince1970)).json")
    }

    static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil,
    ) async -> SpeakSwiftly.Runtime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let persistedConfiguration = resolvedPersistedConfiguration(
            dependencies: dependencies,
            environment: environment,
        )
        let configuredSpeechBackend = resolvedSpeechBackend(
            environment: environment,
            configuration: configuration
                ?? persistedConfiguration,
        )
        let configuredQwenConditioningStrategy = resolvedQwenConditioningStrategy(
            configuration: configuration
                ?? persistedConfiguration,
        )
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride],
            ),
            fileManager: dependencies.fileManager,
        )
        let generatedFileStore = GeneratedFileStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true),
        )
        let generationJobStore = GenerationJobStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true),
        )
        let textProfilesURL = profileStore.rootURL.appending(path: ProfileStore.textProfilesFileName)
        let normalizer = configuration?.textNormalizer
            ?? makeDefaultNormalizer(
                persistenceURL: textProfilesURL,
                dependencies: dependencies,
            )
        let playbackController = await PlaybackController(driver: dependencies.makePlaybackController())

        let runtime = SpeakSwiftly.Runtime(
            dependencies: dependencies,
            speechBackend: configuredSpeechBackend,
            qwenConditioningStrategy: configuredQwenConditioningStrategy,
            profileStore: profileStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            normalizer: normalizer,
            playbackController: playbackController,
        )
        await runtime.installPlaybackHooks()
        return runtime
    }

    static func resolvedSpeechBackend(
        environment: [String: String],
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.SpeechBackend {
        if let configuration {
            return configuration.speechBackend
        }

        if let environmentBackend = SpeakSwiftly.SpeechBackend.configured(in: environment) {
            return environmentBackend
        }

        return .qwen3
    }

    static func resolvedSpeechBackend(
        dependencies _: WorkerDependencies,
        environment: [String: String],
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.SpeechBackend {
        resolvedSpeechBackend(
            environment: environment,
            configuration: configuration,
        )
    }

    static func resolvedQwenConditioningStrategy(
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.QwenConditioningStrategy {
        configuration?.qwenConditioningStrategy ?? .preparedConditioning
    }

    private static func resolvedPersistedConfiguration(
        dependencies: WorkerDependencies,
        environment: [String: String],
    ) -> SpeakSwiftly.Configuration? {
        do {
            return try SpeakSwiftly.Configuration.loadDefault(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride],
            )
        } catch {
            let configurationPath = SpeakSwiftly.Configuration.defaultPersistenceURL(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride],
            )
            .path
            let message = "SpeakSwiftly could not load persisted runtime configuration from '\(configurationPath)'. Falling back to the default runtime configuration. \(error.localizedDescription)\n"
            dependencies.writeStderr(message)
            return nil
        }
    }
}
