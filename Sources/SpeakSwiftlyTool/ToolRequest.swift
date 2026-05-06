import Foundation
import SpeakSwiftly
import TextForSpeech

enum ToolPlaybackAction: Equatable {
    case pause
    case resume
    case state
}

enum ToolSpeechJobType: Equatable {
    case live
    case file
}

enum ToolRequest: Equatable {
    case speech(
        id: String,
        text: String,
        voiceProfile: SpeakSwiftly.Name?,
        textProfileID: SpeakSwiftly.TextProfileID?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    )
    case audio(
        id: String,
        text: String,
        voiceProfile: SpeakSwiftly.Name?,
        textProfileID: SpeakSwiftly.TextProfileID?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
    )
    case batch(id: String, voiceProfile: SpeakSwiftly.Name?, items: [SpeakSwiftly.BatchItem])
    case generatedFile(id: String, artifactID: String)
    case generatedFiles(id: String)
    case generatedBatch(id: String, batchID: String)
    case generatedBatches(id: String)
    case expireGenerationJob(id: String, jobID: String)
    case generationJob(id: String, jobID: String)
    case generationJobs(id: String)
    case createVoiceProfile(
        id: String,
        profileName: SpeakSwiftly.Name,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    )
    case createBuiltInVoiceProfile(
        id: String,
        profileName: SpeakSwiftly.Name,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        seed: SpeakSwiftly.ProfileSeed,
        outputPath: String?,
        cwd: String?,
    )
    case createVoiceClone(
        id: String,
        profileName: SpeakSwiftly.Name,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?,
    )
    case listProfiles(id: String)
    case renameProfile(id: String, profileName: SpeakSwiftly.Name, newProfileName: SpeakSwiftly.Name)
    case rerollProfile(id: String, profileName: SpeakSwiftly.Name)
    case removeProfile(id: String, profileName: SpeakSwiftly.Name)
    case textProfileActive(id: String)
    case textProfile(id: String, profileID: SpeakSwiftly.TextProfileID)
    case textProfiles(id: String)
    case activeTextProfileStyle(id: String)
    case textProfileStyleOptions(id: String)
    case textProfileEffective(id: String)
    case textProfilePersistence(id: String)
    case loadTextProfiles(id: String)
    case saveTextProfiles(id: String)
    case setActiveTextProfileStyle(id: String, style: TextForSpeech.BuiltInProfileStyle)
    case createTextProfile(id: String, profileName: String)
    case renameTextProfile(id: String, profileID: SpeakSwiftly.TextProfileID, profileName: String)
    case setActiveTextProfile(id: String, profileID: SpeakSwiftly.TextProfileID)
    case deleteTextProfile(id: String, profileID: SpeakSwiftly.TextProfileID)
    case factoryResetTextProfiles(id: String)
    case resetTextProfile(id: String, profileID: SpeakSwiftly.TextProfileID)
    case addTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileID: SpeakSwiftly.TextProfileID?)
    case replaceTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileID: SpeakSwiftly.TextProfileID?)
    case removeTextReplacement(id: String, replacementID: String, profileID: SpeakSwiftly.TextProfileID?)
    case listQueue(id: String, queueType: SpeakSwiftly.QueueType)
    case status(id: String)
    case overview(id: String)
    case defaultVoiceProfile(id: String)
    case setDefaultVoiceProfile(id: String, profileName: SpeakSwiftly.Name)
    case switchSpeechBackend(id: String, speechBackend: SpeakSwiftly.SpeechBackend)
    case reloadModels(id: String)
    case unloadModels(id: String)
    case playback(id: String, action: ToolPlaybackAction)
    case clearQueue(id: String, queueType: SpeakSwiftly.QueueType?)
    case cancelRequest(id: String, requestID: String, queueType: SpeakSwiftly.QueueType?)

    static let runtimeDefaultVoiceProfilePlaceholder = "__speakswiftly_runtime_default_voice_profile__"

    var id: String {
        switch self {
            case let .speech(id, _, _, _, _, _, _),
                 let .audio(id, _, _, _, _, _),
                 let .batch(id, _, _),
                 let .generatedFile(id, _),
                 let .generatedFiles(id),
                 let .generatedBatch(id, _),
                 let .generatedBatches(id),
                 let .expireGenerationJob(id, _),
                 let .generationJob(id, _),
                 let .generationJobs(id),
                 let .createVoiceProfile(id, _, _, _, _, _, _),
                 let .createBuiltInVoiceProfile(id, _, _, _, _, _, _, _),
                 let .createVoiceClone(id, _, _, _, _, _),
                 let .listProfiles(id),
                 let .renameProfile(id, _, _),
                 let .rerollProfile(id, _),
                 let .removeProfile(id, _),
                 let .textProfileActive(id),
                 let .textProfile(id, _),
                 let .textProfiles(id),
                 let .activeTextProfileStyle(id),
                 let .textProfileStyleOptions(id),
                 let .textProfileEffective(id),
                 let .textProfilePersistence(id),
                 let .loadTextProfiles(id),
                 let .saveTextProfiles(id),
                 let .setActiveTextProfileStyle(id, _),
                 let .createTextProfile(id, _),
                 let .renameTextProfile(id, _, _),
                 let .setActiveTextProfile(id, _),
                 let .deleteTextProfile(id, _),
                 let .factoryResetTextProfiles(id),
                 let .resetTextProfile(id, _),
                 let .addTextReplacement(id, _, _),
                 let .replaceTextReplacement(id, _, _),
                 let .removeTextReplacement(id, _, _),
                 let .listQueue(id, _),
                 let .status(id),
                 let .overview(id),
                 let .defaultVoiceProfile(id),
                 let .setDefaultVoiceProfile(id, _),
                 let .switchSpeechBackend(id, _),
                 let .reloadModels(id),
                 let .unloadModels(id),
                 let .playback(id, _),
                 let .clearQueue(id, _),
                 let .cancelRequest(id, _, _):
                id
        }
    }

    @discardableResult
    func submit(to runtime: SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle {
        let tool = runtime.tool
        switch self {
            case let .speech(id, text, voiceProfile, textProfileID, sourceFormat, requestContext, qwenPreModelTextChunking):
                return await tool.speech(
                    requestID: id,
                    text: text,
                    voiceProfile: voiceProfile,
                    textProfile: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                )
            case let .audio(id, text, voiceProfile, textProfileID, sourceFormat, requestContext):
                return await tool.audio(
                    requestID: id,
                    text: text,
                    voiceProfile: voiceProfile,
                    textProfile: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                )
            case let .batch(id, voiceProfile, items):
                return await tool.batch(requestID: id, items, voiceProfile: voiceProfile)
            case let .generatedFile(id, artifactID):
                return await tool.artifact(requestID: id, artifactID: artifactID)
            case let .generatedFiles(id):
                return await tool.artifacts(requestID: id)
            case let .generatedBatch(id, batchID):
                return await tool.generatedBatch(requestID: id, batchID: batchID)
            case let .generatedBatches(id):
                return await tool.generatedBatches(requestID: id)
            case let .expireGenerationJob(id, jobID):
                return await tool.expireGenerationJob(requestID: id, jobID: jobID)
            case let .generationJob(id, jobID):
                return await tool.generationJob(requestID: id, jobID: jobID)
            case let .generationJobs(id):
                return await tool.generationJobs(requestID: id)
            case let .createVoiceProfile(id, profileName, text, vibe, voiceDescription, outputPath, cwd):
                return await tool.createVoiceProfile(
                    requestID: id,
                    design: profileName,
                    from: text,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath,
                    cwd: cwd,
                )
            case let .createBuiltInVoiceProfile(id, profileName, text, vibe, voiceDescription, seed, outputPath, cwd):
                return await tool.createBuiltInVoiceProfile(
                    requestID: id,
                    design: profileName,
                    from: text,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    seed: seed,
                    outputPath: outputPath,
                    cwd: cwd,
                )
            case let .createVoiceClone(id, profileName, referenceAudioPath, vibe, transcript, cwd):
                return await tool.createVoiceProfile(
                    requestID: id,
                    clone: profileName,
                    from: URL(fileURLWithPath: referenceAudioPath),
                    vibe: vibe,
                    transcript: transcript,
                    cwd: cwd,
                )
            case let .listProfiles(id):
                return await tool.voiceProfiles(requestID: id)
            case let .renameProfile(id, profileName, newProfileName):
                return await tool.renameVoiceProfile(requestID: id, profileName, to: newProfileName)
            case let .rerollProfile(id, profileName):
                return await tool.rerollVoiceProfile(requestID: id, profileName)
            case let .removeProfile(id, profileName):
                return await tool.deleteVoiceProfile(requestID: id, named: profileName)
            case let .textProfileActive(id):
                return await tool.activeTextProfile(requestID: id)
            case let .textProfile(id, profileID):
                return await tool.textProfile(requestID: id, profileID: profileID)
            case let .textProfiles(id):
                return await tool.textProfiles(requestID: id)
            case let .activeTextProfileStyle(id):
                return await tool.activeTextProfileStyle(requestID: id)
            case let .textProfileStyleOptions(id):
                return await tool.textProfileStyles(requestID: id)
            case let .textProfileEffective(id):
                return await tool.effectiveTextProfile(requestID: id)
            case let .textProfilePersistence(id):
                return await tool.textProfilePersistence(requestID: id)
            case let .loadTextProfiles(id):
                return await tool.loadTextProfiles(requestID: id)
            case let .saveTextProfiles(id):
                return await tool.saveTextProfiles(requestID: id)
            case let .setActiveTextProfileStyle(id, style):
                return await tool.setActiveTextProfileStyle(requestID: id, to: style)
            case let .createTextProfile(id, profileName):
                return await tool.createTextProfile(requestID: id, name: profileName)
            case let .renameTextProfile(id, profileID, profileName):
                return await tool.renameTextProfile(requestID: id, profileID: profileID, to: profileName)
            case let .setActiveTextProfile(id, profileID):
                return await tool.setActiveTextProfile(requestID: id, profileID: profileID)
            case let .deleteTextProfile(id, profileID):
                return await tool.deleteTextProfile(requestID: id, profileID: profileID)
            case let .factoryResetTextProfiles(id):
                return await tool.factoryResetTextProfiles(requestID: id)
            case let .resetTextProfile(id, profileID):
                return await tool.resetTextProfile(requestID: id, profileID: profileID)
            case let .addTextReplacement(id, replacement, profileID):
                return await tool.addTextReplacement(requestID: id, replacement, profileID: profileID)
            case let .replaceTextReplacement(id, replacement, profileID):
                return await tool.replaceTextReplacement(requestID: id, replacement, profileID: profileID)
            case let .removeTextReplacement(id, replacementID, profileID):
                return await tool.deleteTextReplacement(requestID: id, replacementID: replacementID, profileID: profileID)
            case let .listQueue(id, .generation):
                return await tool.generationQueue(requestID: id)
            case let .listQueue(id, .playback):
                return await tool.playbackQueue(requestID: id)
            case let .status(id):
                return await tool.status(requestID: id)
            case let .overview(id):
                return await tool.overview(requestID: id)
            case let .defaultVoiceProfile(id):
                return await tool.defaultVoiceProfile(requestID: id)
            case let .setDefaultVoiceProfile(id, profileName):
                return await tool.setDefaultVoiceProfile(requestID: id, to: profileName)
            case let .switchSpeechBackend(id, speechBackend):
                return await tool.switchSpeechBackend(requestID: id, to: speechBackend)
            case let .reloadModels(id):
                return await tool.reloadModels(requestID: id)
            case let .unloadModels(id):
                return await tool.unloadModels(requestID: id)
            case let .playback(id, .pause):
                return await tool.pausePlayback(requestID: id)
            case let .playback(id, .resume):
                return await tool.resumePlayback(requestID: id)
            case let .playback(id, .state):
                return await tool.playbackState(requestID: id)
            case let .clearQueue(id, queueType):
                return await tool.clearQueue(requestID: id, queueType: queueType)
            case let .cancelRequest(id, requestID, queueType):
                return await tool.cancelRequest(requestID: id, targetRequestID: requestID, queueType: queueType)
        }
    }
}

extension ToolRequest {
    static func queueSpeech(
        id: String,
        text: String,
        profileName: SpeakSwiftly.Name?,
        textProfileID: SpeakSwiftly.TextProfileID?,
        jobType: ToolSpeechJobType,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool?,
    ) -> ToolRequest {
        let voiceProfile = resolvedVoiceProfile(profileName)
        switch jobType {
            case .live:
                return .speech(
                    id: id,
                    text: text,
                    voiceProfile: voiceProfile,
                    textProfileID: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking ?? false,
                )
            case .file:
                return .audio(
                    id: id,
                    text: text,
                    voiceProfile: voiceProfile,
                    textProfileID: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                )
        }
    }

    static func queueBatch(
        id: String,
        profileName: SpeakSwiftly.Name?,
        items: [SpeakSwiftly.GenerationJobItem],
    ) -> ToolRequest {
        .batch(
            id: id,
            voiceProfile: resolvedVoiceProfile(profileName),
            items: items.map {
                SpeakSwiftly.BatchItem(
                    artifactID: $0.artifactID,
                    text: $0.text,
                    textProfile: $0.textProfile,
                    sourceFormat: $0.sourceFormat,
                    requestContext: $0.requestContext,
                )
            },
        )
    }

    static func createProfile(
        id: String,
        profileName: SpeakSwiftly.Name,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        author: SpeakSwiftly.ProfileAuthor,
        seed: SpeakSwiftly.ProfileSeed?,
        outputPath: String?,
        cwd: String?,
    ) -> ToolRequest {
        switch author {
            case .user:
                .createVoiceProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath,
                    cwd: cwd,
                )
            case .system:
                .createBuiltInVoiceProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    seed: seed ?? SpeakSwiftly.ProfileSeed(
                        seedID: profileName,
                        seedVersion: "unknown",
                        intendedProfileName: profileName,
                        installedAt: Date(timeIntervalSince1970: 0),
                        sourcePackage: "unknown",
                    ),
                    outputPath: outputPath,
                    cwd: cwd,
                )
        }
    }

    static func createClone(
        id: String,
        profileName: SpeakSwiftly.Name,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?,
    ) -> ToolRequest {
        .createVoiceClone(
            id: id,
            profileName: profileName,
            referenceAudioPath: referenceAudioPath,
            vibe: vibe,
            transcript: transcript,
            cwd: cwd,
        )
    }

    func resolvingRuntimeDefaultVoiceProfile(_ defaultVoiceProfileName: SpeakSwiftly.Name) -> ToolRequest {
        switch self {
            case let .speech(id, text, nil, textProfileID, sourceFormat, requestContext, qwenPreModelTextChunking):
                .speech(
                    id: id,
                    text: text,
                    voiceProfile: defaultVoiceProfileName,
                    textProfileID: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                )
            case let .audio(id, text, nil, textProfileID, sourceFormat, requestContext):
                .audio(
                    id: id,
                    text: text,
                    voiceProfile: defaultVoiceProfileName,
                    textProfileID: textProfileID,
                    sourceFormat: sourceFormat,
                    requestContext: requestContext,
                )
            case let .batch(id, nil, items):
                .batch(id: id, voiceProfile: defaultVoiceProfileName, items: items)
            default:
                self
        }
    }

    private static func resolvedVoiceProfile(_ profileName: SpeakSwiftly.Name?) -> SpeakSwiftly.Name? {
        profileName == runtimeDefaultVoiceProfilePlaceholder ? nil : profileName
    }
}
