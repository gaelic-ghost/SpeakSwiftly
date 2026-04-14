import Foundation
import TextForSpeech

// MARK: - WorkerRequest

enum WorkerRequest: Equatable {
    case queueSpeech(
        id: String,
        text: String,
        profileName: String,
        textProfileName: String?,
        jobType: SpeechJobType,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?,
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
    case textProfile(id: String, name: String)
    case textProfiles(id: String)
    case textProfileStyle(id: String)
    case textProfileEffective(id: String, name: String?)
    case textProfilePersistence(id: String)
    case loadTextProfiles(id: String)
    case saveTextProfiles(id: String)
    case setTextProfileStyle(id: String, style: TextForSpeech.BuiltInProfileStyle)
    case createTextProfile(id: String, profileID: String, profileName: String, replacements: [TextForSpeech.Replacement])
    case storeTextProfile(id: String, profile: TextForSpeech.Profile)
    case useTextProfile(id: String, profile: TextForSpeech.Profile)
    case removeTextProfile(id: String, profileName: String)
    case resetTextProfile(id: String)
    case textReplacements(id: String, profileName: String?)
    case addTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileName: String?)
    case replaceTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileName: String?)
    case removeTextReplacement(id: String, replacementID: String, profileName: String?)
    case clearTextReplacements(id: String, profileName: String?)
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
            case .queueSpeech(id: let id, text: _, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: _),
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
                 let .textProfileStyle(id),
                 let .textProfileEffective(id, _),
                 let .textProfilePersistence(id),
                 let .loadTextProfiles(id),
                 let .saveTextProfiles(id),
                 let .setTextProfileStyle(id, _),
                 let .createTextProfile(id, _, _, _),
                 let .storeTextProfile(id, _),
                 let .useTextProfile(id, _),
                 let .removeTextProfile(id, _),
                 let .resetTextProfile(id),
                 let .textReplacements(id, _),
                 let .addTextReplacement(id, _, _),
                 let .replaceTextReplacement(id, _, _),
                 let .removeTextReplacement(id, _, _),
                 let .clearTextReplacements(id, _),
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
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
                "generate_speech"
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _):
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
            case .textProfileStyle:
                "get_text_profile_style"
            case .textProfileEffective:
                "get_effective_text_profile"
            case .textProfilePersistence:
                "get_text_profile_persistence"
            case .loadTextProfiles:
                "load_text_profiles"
            case .saveTextProfiles:
                "save_text_profiles"
            case .setTextProfileStyle:
                "set_text_profile_style"
            case .createTextProfile:
                "create_text_profile"
            case .storeTextProfile:
                "replace_text_profile"
            case .useTextProfile:
                "replace_active_text_profile"
            case .removeTextProfile:
                "delete_text_profile"
            case .resetTextProfile:
                "reset_text_profile"
            case .textReplacements:
                "list_text_replacements"
            case .addTextReplacement:
                "create_text_replacement"
            case .replaceTextReplacement:
                "replace_text_replacement"
            case .removeTextReplacement:
                "delete_text_replacement"
            case .clearTextReplacements:
                "clear_text_replacements"
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
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
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
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _),
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
                 .textProfileStyle,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setTextProfileStyle,
                 .createTextProfile,
                 .storeTextProfile,
                 .useTextProfile,
                 .removeTextProfile,
                 .resetTextProfile,
                 .textReplacements,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .clearTextReplacements,
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

    var profileName: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileName: _, jobType: _, textContext: _, sourceFormat: _),
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
                 .textProfileStyle,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setTextProfileStyle,
                 .storeTextProfile,
                 .useTextProfile,
                 .resetTextProfile,
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
            case let .textProfile(_, name),
                 let .removeTextProfile(_, name):
                name
            case let .textProfileEffective(_, name),
                 let .textReplacements(_, name),
                 let .addTextReplacement(_, _, name),
                 let .replaceTextReplacement(_, _, name),
                 let .removeTextReplacement(_, _, name),
                 let .clearTextReplacements(_, name):
                name
            case let .createTextProfile(_, profileID, _, _):
                profileID
        }
    }

    var textProfileName: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: let textProfileName, jobType: _, textContext: _, sourceFormat: _):
                return textProfileName
            case .queueBatch(id: _, profileName: _, items: let items):
                let names = Set(items.compactMap(\.textProfileName))
                return names.count == 1 ? names.first : nil
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
                 .textProfileStyle,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setTextProfileStyle,
                 .createTextProfile,
                 .storeTextProfile,
                 .useTextProfile,
                 .removeTextProfile,
                 .resetTextProfile,
                 .textReplacements,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .clearTextReplacements,
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
        }
    }

    var textContext: TextForSpeech.Context? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: _, textContext: let textContext, sourceFormat: _):
                textContext
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
                 .textProfileStyle,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setTextProfileStyle,
                 .createTextProfile,
                 .storeTextProfile,
                 .useTextProfile,
                 .removeTextProfile,
                 .resetTextProfile,
                 .textReplacements,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .clearTextReplacements,
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

    var sourceFormat: TextForSpeech.SourceFormat? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: let sourceFormat):
                sourceFormat
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
                 .textProfileStyle,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setTextProfileStyle,
                 .createTextProfile,
                 .storeTextProfile,
                 .useTextProfile,
                 .removeTextProfile,
                 .resetTextProfile,
                 .textReplacements,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .clearTextReplacements,
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
