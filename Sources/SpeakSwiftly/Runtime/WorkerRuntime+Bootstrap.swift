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

    package static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil,
        stateRootURL: URL? = nil,
        systemProfileResourceRootURL: URL? = nil,
        allowsProfileModelCPUFallback: Bool? = nil,
        startsResidentModelsAutomatically: Bool = true,
    ) async -> SpeakSwiftly.Runtime {
        let environment = ProcessInfo.processInfo.environment
        let bootstrapDependencies = WorkerDependencies.live()
        let environmentStateRootOverride = ProfileStore.runtimeStateRootOverride(in: environment)
        let stateRootOverridePath = stateRootURL?.standardizedFileURL.path
            ?? environmentStateRootOverride?.path
        if stateRootURL == nil,
           environmentStateRootOverride?.source == .deprecatedProfileRoot {
            bootstrapDependencies.writeStderr(
                "SpeakSwiftly is using deprecated \(Environment.deprecatedProfileRootOverride)='\(environmentStateRootOverride?.path ?? "")' as the runtime state root. Prefer SpeakSwiftly.liftoff(stateRootURL:), the SpeakSwiftlyTool --state-root option, or \(Environment.runtimeStateRootOverride); SpeakSwiftly derives profiles/, \(ProfileStore.configurationFileName), and \(ProfileStore.textProfilesFileName) from that state root.\n",
            )
        }
        let persistedConfiguration = resolvedPersistedConfiguration(
            dependencies: bootstrapDependencies,
            runtimeStateRootOverridePath: stateRootOverridePath,
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
        let configuredDefaultVoiceProfile = resolvedDefaultVoiceProfile(
            configuration: configuration
                ?? persistedConfiguration,
        )
        let configuredDuckMediaVolume = resolvedDuckMediaVolume(
            configuration: configuration
                ?? persistedConfiguration,
        )
        let configuredAudioOutputDestination = resolvedAudioOutputDestination(
            configuration: configuration
                ?? persistedConfiguration,
        )
        let configuredRecentGeneratedAudioLimit = resolvedRecentGeneratedAudioLimit(
            configuration: configuration
                ?? persistedConfiguration,
        )
        let configuredSystemProfileResourceRoots = configuration?.systemProfileResourceRoots ?? []
        let dependencies = WorkerDependencies.live(
            allowsProfileModelCPUFallback: allowsProfileModelCPUFallback,
            duckMediaVolume: configuredDuckMediaVolume,
        )
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                stateRootOverride: stateRootOverridePath,
            ),
            fileManager: dependencies.fileManager,
        )
        seedSystemProfilesIfAvailable(
            from: configuredSystemProfileResourceRoots,
            into: profileStore,
            dependencies: dependencies,
        )
        let systemProfileResourceStore = systemProfileResourceRootURL.map {
            ProfileStore(
                rootURL: ProfileStore.systemProfileResourceRootURL(from: $0),
                fileManager: dependencies.fileManager,
            )
        }
        let generatedFileStore = GeneratedFileStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true),
        )
        let generationJobStore = GenerationJobStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true),
        )
        let textProfilesURL = ProfileStore.defaultTextProfilesURL(
            fileManager: dependencies.fileManager,
            stateRootOverride: stateRootOverridePath,
        )
        let normalizer = configuration?.textNormalizer
            ?? makeDefaultNormalizer(
                persistenceURL: textProfilesURL,
                dependencies: dependencies,
            )
        let playbackQueue = await PlaybackQueue(driver: dependencies.makePlaybackDriver())

        let runtime = SpeakSwiftly.Runtime(
            dependencies: dependencies,
            speechBackend: configuredSpeechBackend,
            qwenConditioningStrategy: configuredQwenConditioningStrategy,
            duckMediaVolume: configuredDuckMediaVolume,
            audioOutputDestination: configuredAudioOutputDestination,
            defaultVoiceProfileName: configuredDefaultVoiceProfile,
            profileStore: profileStore,
            systemProfileResourceStore: systemProfileResourceStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            recentGeneratedAudioStore: SpeakSwiftly.RecentGeneratedAudioStore(
                limit: configuredRecentGeneratedAudioLimit,
            ),
            recentGeneratedAudioLimit: configuredRecentGeneratedAudioLimit,
            normalizer: normalizer,
            playbackQueue: playbackQueue,
            startsResidentModelsAutomatically: startsResidentModelsAutomatically,
        )
        await runtime.installPlaybackHooks()
        return runtime
    }

    private static func seedSystemProfilesIfAvailable(
        from configuredResourceRootURLs: [URL],
        into profileStore: ProfileStore,
        dependencies: WorkerDependencies,
    ) {
        var seedRoots: [(source: String, url: URL)] = []

        if let bundledRootURL = SpeakSwiftly.SupportResources.bundledSystemProfileRootURL(
            fileManager: dependencies.fileManager,
        ) {
            seedRoots.append(("SpeakSwiftly bundled", bundledRootURL))
        }

        seedRoots.append(
            contentsOf: configuredResourceRootURLs.map {
                ("configured", ProfileStore.systemProfileResourceRootURL(from: $0))
            },
        )

        for seedRoot in seedRoots {
            seedSystemProfilesIfAvailable(
                from: seedRoot.url,
                source: seedRoot.source,
                into: profileStore,
                dependencies: dependencies,
            )
        }
    }

    private static func seedSystemProfilesIfAvailable(
        from resourceRootURL: URL,
        source: String,
        into profileStore: ProfileStore,
        dependencies: WorkerDependencies,
    ) {
        do {
            let summary = try profileStore.seedSystemProfiles(from: resourceRootURL)
            guard summary.changedCount > 0 else { return }

            dependencies.writeStderr(
                "SpeakSwiftly seeded \(summary.installedCount) \(source) system voice profile(s) and refreshed \(summary.replacedCount) \(source) system voice profile(s) from '\(resourceRootURL.path)'.\n",
            )
        } catch {
            dependencies.writeStderr(
                "SpeakSwiftly could not seed \(source) system voice profiles from '\(resourceRootURL.path)'. SpeakSwiftly will continue with the existing writable profile store. \(error.localizedDescription)\n",
            )
        }
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

        return .qwen3_smol
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

    static func resolvedDefaultVoiceProfile(
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.Name {
        SpeakSwiftly.Configuration.normalizedDefaultVoiceProfile(configuration?.defaultVoiceProfile)
    }

    static func resolvedDuckMediaVolume(
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.DuckMediaVolume {
        configuration?.duckMediaVolume ?? .off
    }

    static func resolvedAudioOutputDestination(
        configuration: SpeakSwiftly.Configuration?,
    ) -> SpeakSwiftly.AudioOutputDestination {
        configuration?.audioOutputDestination ?? .localPlayback
    }

    static func resolvedRecentGeneratedAudioLimit(
        configuration: SpeakSwiftly.Configuration?,
    ) -> Int {
        configuration?.recentGeneratedAudioLimit ?? 5
    }

    func setDefaultVoiceProfileName(_ profileName: SpeakSwiftly.Name) throws {
        let resolvedProfileName = SpeakSwiftly.Configuration.normalizedDefaultVoiceProfile(profileName)
        defaultVoiceProfileName = resolvedProfileName
        try currentConfiguration().saveDefault(
            fileManager: dependencies.fileManager,
            stateRootOverride: profileStore.stateRootURL.path,
        )
        broadcastRuntimeUpdate(recordRuntimeUpdate(state: currentRuntimeState))
    }

    func currentConfiguration() -> SpeakSwiftly.Configuration {
        SpeakSwiftly.Configuration(
            speechBackend: speechBackend,
            qwenConditioningStrategy: qwenConditioningStrategy,
            defaultVoiceProfile: defaultVoiceProfileName,
            duckMediaVolume: duckMediaVolume,
            audioOutputDestination: audioOutputDestination,
            recentGeneratedAudioLimit: recentGeneratedAudioLimit,
            textNormalizer: normalizerRef,
        )
    }

    private static func resolvedPersistedConfiguration(
        dependencies: WorkerDependencies,
        runtimeStateRootOverridePath: String?,
    ) -> SpeakSwiftly.Configuration? {
        do {
            return try SpeakSwiftly.Configuration.loadDefault(
                fileManager: dependencies.fileManager,
                stateRootOverride: runtimeStateRootOverridePath,
            )
        } catch {
            let configurationPath = SpeakSwiftly.Configuration.defaultPersistenceURL(
                fileManager: dependencies.fileManager,
                stateRootOverride: runtimeStateRootOverridePath,
            )
            .path
            let message = "SpeakSwiftly could not load persisted runtime configuration from '\(configurationPath)'. Falling back to the default runtime configuration. \(error.localizedDescription)\n"
            dependencies.writeStderr(message)
            return nil
        }
    }
}
