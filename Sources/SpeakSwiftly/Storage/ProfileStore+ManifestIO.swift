import Foundation
import MLXAudioTTS

// MARK: - ProfileStore Manifest IO

extension ProfileStore {
    func loadManifest(from directoryURL: URL) throws -> ProfileManifest {
        let manifestPath = manifestURL(for: directoryURL)
        let manifestData = try Data(contentsOf: manifestPath)
        let requiresLegacyQwenNormalization = manifestDataRequiresLegacyQwenNormalization(manifestData)
        let decodableManifestData = normalizedLegacyQwenBackendManifestData(manifestData) ?? manifestData

        if let manifest = try? decoder.decode(ProfileManifest.self, from: decodableManifestData) {
            let upgradedManifest = upgradeStoredManifest(manifest)
            if requiresLegacyQwenNormalization || decodableManifestData != manifestData || upgradedManifest != manifest {
                try writeManifest(upgradedManifest, to: directoryURL)
            }
            return upgradedManifest
        }

        if let legacyManifest = try? decoder.decode(LegacyMultiBackendProfileManifest.self, from: decodableManifestData) {
            let upgradedManifest = upgradeLegacyMultiBackendManifest(legacyManifest)
            try writeManifest(upgradedManifest, to: directoryURL)
            return upgradedManifest
        }

        if let legacyManifest = try? decoder.decode(LegacyProfileManifest.self, from: decodableManifestData) {
            let upgradedManifest = upgradeLegacyManifest(legacyManifest)
            try writeManifest(upgradedManifest, to: directoryURL)
            return upgradedManifest
        }

        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not read the profile manifest at '\(manifestPath.path)' because the file is unreadable or corrupt.",
        )
    }

    func upgradeLegacyManifest(_ legacyManifest: LegacyProfileManifest) -> ProfileManifest {
        let sourceKind: ProfileSourceKind = legacyManifest.modelRepo == ModelFactory.importedCloneModelRepo
            ? .importedClone
            : .generated
        let materializations = [
            ProfileMaterializationManifest(
                backend: .qwen3_smol,
                modelRepo: ModelFactory.residentModelRepo(for: .qwen3_smol),
                createdAt: legacyManifest.createdAt,
                referenceAudioFile: legacyManifest.referenceAudioFile,
                referenceText: legacyManifest.sourceText,
                sampleRate: legacyManifest.sampleRate,
            ),
        ]

        return ProfileManifest(
            version: Self.manifestVersion,
            profileName: legacyManifest.profileName,
            vibe: inferredLegacyVibe(
                profileName: legacyManifest.profileName,
                voiceDescription: legacyManifest.voiceDescription,
            ),
            createdAt: legacyManifest.createdAt,
            sourceKind: sourceKind,
            modelRepo: legacyManifest.modelRepo,
            voiceDescription: legacyManifest.voiceDescription,
            sourceText: legacyManifest.sourceText,
            transcriptProvenance: nil,
            author: .user,
            seed: nil,
            sampleRate: legacyManifest.sampleRate,
            backendMaterializations: materializations,
            qwenConditioningArtifacts: [],
        )
    }

    func upgradeLegacyMultiBackendManifest(_ legacyManifest: LegacyMultiBackendProfileManifest) -> ProfileManifest {
        let qwenMaterializations = legacyManifest.backendMaterializations.filter(\.backend.isQwenFamily)
        let materializations = if qwenMaterializations.isEmpty {
            [
                ProfileMaterializationManifest(
                    backend: .qwen3_smol,
                    modelRepo: ModelFactory.residentModelRepo(for: .qwen3_smol),
                    createdAt: legacyManifest.createdAt,
                    referenceAudioFile: Self.audioFileName,
                    referenceText: legacyManifest.sourceText,
                    sampleRate: legacyManifest.sampleRate,
                ),
            ]
        } else {
            qwenMaterializations
        }

        return ProfileManifest(
            version: Self.manifestVersion,
            profileName: legacyManifest.profileName,
            vibe: inferredLegacyVibe(
                profileName: legacyManifest.profileName,
                voiceDescription: legacyManifest.voiceDescription,
            ),
            createdAt: legacyManifest.createdAt,
            sourceKind: legacyManifest.sourceKind,
            modelRepo: legacyManifest.modelRepo,
            voiceDescription: legacyManifest.voiceDescription,
            sourceText: legacyManifest.sourceText,
            transcriptProvenance: nil,
            author: .user,
            seed: nil,
            sampleRate: legacyManifest.sampleRate,
            backendMaterializations: materializations,
            qwenConditioningArtifacts: [],
        )
    }

    func upgradeStoredManifest(_ manifest: ProfileManifest) -> ProfileManifest {
        let normalizedMaterializations = manifest.backendMaterializations.map(normalizeQwenMaterialization)
        let normalizedArtifacts = manifest.qwenConditioningArtifacts.map(normalizeQwenConditioningArtifactManifest)
        let normalizedVersion = max(manifest.version, Self.manifestVersion)

        return ProfileManifest(
            version: normalizedVersion,
            profileName: manifest.profileName,
            vibe: manifest.vibe,
            createdAt: manifest.createdAt,
            sourceKind: manifest.sourceKind,
            modelRepo: manifest.modelRepo,
            voiceDescription: manifest.voiceDescription,
            sourceText: manifest.sourceText,
            transcriptProvenance: manifest.transcriptProvenance,
            author: manifest.author,
            seed: manifest.seed,
            sampleRate: manifest.sampleRate,
            backendMaterializations: normalizedMaterializations,
            qwenConditioningArtifacts: normalizedArtifacts,
        )
    }

    func manifestDataRequiresLegacyQwenNormalization(_ manifestData: Data) -> Bool {
        guard let manifestText = String(data: manifestData, encoding: .utf8) else {
            return false
        }

        return manifestText.contains("qwen3_custom_voice")
            || manifestText.contains(#""backend" : "qwen3""#)
            || manifestText.contains(#""backend":"qwen3""#)
            || manifestText.contains(ModelFactory.legacyQwenCustomVoiceResidentModelRepo)
    }

    func normalizedLegacyQwenBackendManifestData(_ manifestData: Data) -> Data? {
        guard var manifest = try? JSONSerialization.jsonObject(with: manifestData) else {
            return nil
        }

        var changed = false
        normalizeLegacyQwenBackendValues(in: &manifest, changed: &changed)
        guard changed else {
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    func normalizeLegacyQwenBackendValues(in value: inout Any, changed: inout Bool) {
        if var dictionary = value as? [String: Any] {
            if dictionary["backend"] as? String == "qwen3"
                || dictionary["backend"] as? String == "qwen3_custom_voice" {
                dictionary["backend"] = SpeakSwiftly.SpeechBackend.qwen3_smol.rawValue
                changed = true
            }

            for key in dictionary.keys {
                var nestedValue = dictionary[key] as Any
                normalizeLegacyQwenBackendValues(in: &nestedValue, changed: &changed)
                dictionary[key] = nestedValue
            }

            value = dictionary
            return
        }

        if var array = value as? [Any] {
            for index in array.indices {
                var nestedValue = array[index]
                normalizeLegacyQwenBackendValues(in: &nestedValue, changed: &changed)
                array[index] = nestedValue
            }

            value = array
        }
    }

    func normalizeQwenMaterialization(
        _ materialization: ProfileMaterializationManifest,
    ) -> ProfileMaterializationManifest {
        guard materialization.backend.isQwenFamily else {
            return materialization
        }

        return ProfileMaterializationManifest(
            backend: .qwen3_smol,
            modelRepo: ModelFactory.residentModelRepo(for: .qwen3_smol),
            createdAt: materialization.createdAt,
            referenceAudioFile: materialization.referenceAudioFile,
            referenceText: materialization.referenceText,
            sampleRate: materialization.sampleRate,
        )
    }

    func normalizeQwenConditioningArtifactManifest(
        _ manifest: QwenConditioningArtifactManifest,
    ) -> QwenConditioningArtifactManifest {
        guard manifest.backend.isQwenFamily else {
            return manifest
        }

        return QwenConditioningArtifactManifest(
            backend: SpeakSwiftly.SpeechBackend.qwenBackend(
                forResidentModelRepo: normalizedQwenConditioningModelRepo(manifest.modelRepo),
            ) ?? .qwen3_smol,
            modelRepo: normalizedQwenConditioningModelRepo(manifest.modelRepo),
            createdAt: manifest.createdAt,
            artifactVersion: manifest.artifactVersion,
            artifactFile: manifest.artifactFile,
        )
    }

    func normalizedQwenConditioningModelRepo(_ modelRepo: String) -> String {
        switch modelRepo {
            case ModelFactory.qwen06B8BitResidentModelRepo,
                 ModelFactory.qwen06B4BitResidentModelRepo,
                 ModelFactory.qwen06B5BitResidentModelRepo,
                 ModelFactory.qwen06B6BitResidentModelRepo,
                 ModelFactory.qwen06BBF16ResidentModelRepo,
                 ModelFactory.qwen17B8BitResidentModelRepo,
                 ModelFactory.qwen17B4BitResidentModelRepo,
                 ModelFactory.qwen17B5BitResidentModelRepo,
                 ModelFactory.qwen17B6BitResidentModelRepo,
                 ModelFactory.qwen17BBF16ResidentModelRepo:
                modelRepo
            default:
                ModelFactory.qwenResidentModelRepo
        }
    }

    func inferredLegacyVibe(
        profileName: String,
        voiceDescription: String,
    ) -> SpeakSwiftly.Vibe {
        let signal = "\(profileName) \(voiceDescription)".lowercased()

        if signal.contains("femme")
            || signal.contains("female")
            || signal.contains("feminine")
            || signal.contains("woman")
            || signal.contains("girl") {
            return .femme
        }

        if signal.contains("masc")
            || signal.contains("male")
            || signal.contains("masculine")
            || signal.contains("man")
            || signal.contains("boy") {
            return .masc
        }

        return .femme
    }

    func writeMaterializationFiles(
        _ materializations: [ProfileMaterializationDraft],
        to directoryURL: URL,
    ) throws {
        var writtenFiles = Set<String>()

        for materialization in materializations {
            if writtenFiles.contains(materialization.referenceAudioFile) {
                continue
            }

            try materialization.audioData.write(
                to: referenceAudioURL(for: directoryURL, fileName: materialization.referenceAudioFile),
                options: .atomic,
            )
            writtenFiles.insert(materialization.referenceAudioFile)
        }
    }

    func writeQwenConditioningArtifact(
        _ artifact: PersistedQwenConditioningArtifact,
        to directoryURL: URL,
        fileName: String,
    ) throws {
        let data = try encoder.encode(artifact)
        try data.write(
            to: qwenConditioningArtifactURL(for: directoryURL, fileName: fileName),
            options: .atomic,
        )
    }

    func writeManifest(_ manifest: ProfileManifest, to directoryURL: URL) throws {
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL(for: directoryURL), options: .atomic)
    }

    func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }
}
