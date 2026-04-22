import Foundation
import TextForSpeech

enum WorkerRequest: Equatable {
    case queueSpeech(
        id: String,
        text: String,
        profileName: String,
        textProfileID: String?,
        jobType: SpeechJobType,
        inputTextContext: SpeakSwiftly.InputTextContext?,
        requestContext: SpeakSwiftly.RequestContext?,
    )
    case queueBatch(
        id: String,
        profileName: String,
        items: [SpeakSwiftly.GenerationJobItem],
    )
    case generatedFile(id: String, artifactID: String)
    case generatedFiles(id: String)
    case generatedBatch(id: String, batchID: String)
    case generatedBatches(id: String)
    case expireGenerationJob(id: String, jobID: String)
    case generationJob(id: String, jobID: String)
    case generationJobs(id: String)
    case createProfile(
        id: String,
        profileName: String,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    )
    case createClone(
        id: String,
        profileName: String,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?,
    )
    case listProfiles(id: String)
    case renameProfile(id: String, profileName: String, newProfileName: String)
    case rerollProfile(id: String, profileName: String)
    case removeProfile(id: String, profileName: String)
    case textProfileActive(id: String)
    case textProfile(id: String, profileID: String)
    case textProfiles(id: String)
    case activeTextProfileStyle(id: String)
    case textProfileStyleOptions(id: String)
    case textProfileEffective(id: String)
    case textProfilePersistence(id: String)
    case loadTextProfiles(id: String)
    case saveTextProfiles(id: String)
    case setActiveTextProfileStyle(id: String, style: TextForSpeech.BuiltInProfileStyle)
    case createTextProfile(id: String, profileName: String)
    case renameTextProfile(id: String, profileID: String, profileName: String)
    case setActiveTextProfile(id: String, profileID: String)
    case deleteTextProfile(id: String, profileID: String)
    case factoryResetTextProfiles(id: String)
    case resetTextProfile(id: String, profileID: String)
    case addTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileID: String?)
    case replaceTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileID: String?)
    case removeTextReplacement(id: String, replacementID: String, profileID: String?)
    case listQueue(id: String, queueType: WorkerQueueType)
    case status(id: String)
    case overview(id: String)
    case switchSpeechBackend(id: String, speechBackend: SpeakSwiftly.SpeechBackend)
    case reloadModels(id: String)
    case unloadModels(id: String)
    case playback(id: String, action: PlaybackAction)
    case clearQueue(id: String)
    case cancelRequest(id: String, requestID: String)

    var id: String {
        switch self {
            case .queueSpeech(id: let id, text: _, profileName: _, textProfileID: _, jobType: _, inputTextContext: _, requestContext: _),
                 .queueBatch(id: let id, profileName: _, items: _),
                 let .generatedFile(id, _),
                 let .generatedFiles(id),
                 let .generatedBatch(id, _),
                 let .generatedBatches(id),
                 let .expireGenerationJob(id, _),
                 let .generationJob(id, _),
                 let .generationJobs(id),
                 let .createProfile(id, _, _, _, _, _, _),
                 let .createClone(id, _, _, _, _, _),
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
                 let .switchSpeechBackend(id, _),
                 let .reloadModels(id),
                 let .unloadModels(id),
                 let .playback(id, _),
                 let .clearQueue(id),
                 let .cancelRequest(id, _):
                id
        }
    }

    var opName: String {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .live, inputTextContext: _, requestContext: _):
                "generate_speech"
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .file, inputTextContext: _, requestContext: _):
                "generate_audio_file"
            case .queueBatch:
                "generate_batch"
            case .generatedFile:
                "get_generated_file"
            case .generatedFiles:
                "list_generated_files"
            case .generatedBatch:
                "get_generated_batch"
            case .generatedBatches:
                "list_generated_batches"
            case .expireGenerationJob:
                "expire_generation_job"
            case .generationJob:
                "get_generation_job"
            case .generationJobs:
                "list_generation_jobs"
            case .createProfile:
                "create_voice_profile_from_description"
            case .createClone:
                "create_voice_profile_from_audio"
            case .listProfiles:
                "list_voice_profiles"
            case .renameProfile:
                "update_voice_profile_name"
            case .rerollProfile:
                "reroll_voice_profile"
            case .removeProfile:
                "delete_voice_profile"
            case .textProfileActive:
                "get_active_text_profile"
            case .textProfile:
                "get_text_profile"
            case .textProfiles:
                "list_text_profiles"
            case .activeTextProfileStyle:
                "get_active_text_profile_style"
            case .textProfileStyleOptions:
                "list_text_profile_styles"
            case .textProfileEffective:
                "get_effective_text_profile"
            case .textProfilePersistence:
                "get_text_profile_persistence"
            case .loadTextProfiles:
                "load_text_profiles"
            case .saveTextProfiles:
                "save_text_profiles"
            case .setActiveTextProfileStyle:
                "set_active_text_profile_style"
            case .createTextProfile:
                "create_text_profile"
            case .renameTextProfile:
                "update_text_profile_name"
            case .setActiveTextProfile:
                "set_active_text_profile"
            case .deleteTextProfile:
                "delete_text_profile"
            case .factoryResetTextProfiles:
                "factory_reset_text_profiles"
            case .resetTextProfile:
                "reset_text_profile"
            case .addTextReplacement:
                "create_text_replacement"
            case .replaceTextReplacement:
                "replace_text_replacement"
            case .removeTextReplacement:
                "delete_text_replacement"
            case .listQueue(_, .generation):
                "list_generation_queue"
            case .listQueue(_, .playback):
                "list_playback_queue"
            case .status:
                "get_status"
            case .overview:
                "get_runtime_overview"
            case .switchSpeechBackend:
                "set_speech_backend"
            case .reloadModels:
                "reload_models"
            case .unloadModels:
                "unload_models"
            case .playback(_, .pause):
                "playback_pause"
            case .playback(_, .resume):
                "playback_resume"
            case .playback(_, .state):
                "get_playback_state"
            case .clearQueue:
                "clear_queue"
            case .cancelRequest:
                "cancel_request"
        }
    }

    var isSpeechRequest: Bool {
        switch self {
            case .queueSpeech, .queueBatch:
                true
            default:
                false
        }
    }

    var requiresResidentModels: Bool {
        switch self {
            case .queueSpeech, .queueBatch:
                true
            default:
                false
        }
    }

    var mutatesResidentState: Bool {
        switch self {
            case .switchSpeechBackend, .reloadModels, .unloadModels:
                true
            default:
                false
        }
    }

    var requiresPlayback: Bool {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .live, inputTextContext: _, requestContext: _):
                true
            default:
                false
        }
    }

    var acknowledgesEnqueueImmediately: Bool {
        switch self {
            case .queueSpeech, .queueBatch, .switchSpeechBackend, .reloadModels, .unloadModels:
                true
            default:
                false
        }
    }

    var emitsTerminalSuccessAfterAcknowledgement: Bool {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .file, inputTextContext: _, requestContext: _),
                 .queueBatch,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels:
                true
            default:
                false
        }
    }

    var isImmediateControlOperation: Bool {
        switch self {
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .textProfileActive,
                 .textProfile,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .renameTextProfile,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .factoryResetTextProfiles,
                 .resetTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .listQueue,
                 .status,
                 .overview,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                true
            default:
                false
        }
    }

    var requiresPlaybackDrainBeforeStart: Bool {
        switch self {
            case .switchSpeechBackend, .reloadModels, .unloadModels:
                true
            default:
                false
        }
    }

    var formsOrderedControlBarrier: Bool {
        mutatesResidentState
    }

    var canBypassParkedResidentWork: Bool {
        mutatesResidentState
    }

    var voiceProfile: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileID: _, jobType: _, inputTextContext: _, requestContext: _),
                 .queueBatch(id: _, profileName: let profileName, items: _),
                 let .createProfile(_, profileName, _, _, _, _, _),
                 let .createClone(_, profileName, _, _, _, _),
                 let .renameProfile(_, profileName, _),
                 let .rerollProfile(_, profileName),
                 let .removeProfile(_, profileName):
                profileName
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .textProfileActive,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .factoryResetTextProfiles,
                 .listProfiles,
                 .listQueue,
                 .status,
                 .overview,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                nil
            case let .renameTextProfile(_, _, profileName):
                profileName
            case .textProfile,
                 .textProfileEffective,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .resetTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement:
                nil
        }
    }

    var textProfileID: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: let textProfileID, jobType: _, inputTextContext: _, requestContext: _):
                return textProfileID
            case .queueBatch(id: _, profileName: _, items: let items):
                let ids = Set(items.compactMap(\.textProfile))
                return ids.count == 1 ? ids.first : nil
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .renameProfile,
                 .rerollProfile,
                 .removeProfile,
                 .textProfileActive,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .factoryResetTextProfiles,
                 .listQueue,
                 .status,
                 .overview,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                return nil
            case let .textProfile(_, profileID),
                 let .renameTextProfile(_, profileID, _),
                 let .setActiveTextProfile(_, profileID),
                 let .deleteTextProfile(_, profileID),
                 let .resetTextProfile(_, profileID):
                return profileID
            case let .addTextReplacement(_, _, profileID),
                 let .replaceTextReplacement(_, _, profileID),
                 let .removeTextReplacement(_, _, profileID):
                return profileID
            case .textProfileEffective:
                return nil
        }
    }

    var inputTextContext: SpeakSwiftly.InputTextContext? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: _, inputTextContext: let inputTextContext, requestContext: _):
                inputTextContext
            case .queueBatch:
                nil
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .renameProfile,
                 .rerollProfile,
                 .removeProfile,
                 .textProfileActive,
                 .textProfile,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .renameTextProfile,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .factoryResetTextProfiles,
                 .resetTextProfile,
                 .listQueue,
                 .status,
                 .overview,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                nil
        }
    }

    var requestContext: SpeakSwiftly.RequestContext? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: _, inputTextContext: _, requestContext: let requestContext):
                requestContext
            case .queueBatch:
                nil
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .renameProfile,
                 .rerollProfile,
                 .removeProfile,
                 .textProfileActive,
                 .textProfile,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .renameTextProfile,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .factoryResetTextProfiles,
                 .resetTextProfile,
                 .listQueue,
                 .status,
                 .overview,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                nil
        }
    }
}
