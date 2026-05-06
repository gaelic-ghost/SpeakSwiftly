import Foundation

/// The top-level namespace and startup entrypoint for the SpeakSwiftly library.
///
/// Use ``liftoff(configuration:stateRootURL:)`` to create a shared ``Runtime`` and then work
/// through the runtime's typed concern handles such as ``SpeakSwiftly/Runtime/generate``
/// and ``SpeakSwiftly/Runtime/playback``.
public enum SpeakSwiftly {
    // MARK: Internal Request Helpers

    enum SpeechJobType: Equatable {
        case live
        case file
    }

    enum PlaybackAction: Equatable {
        case pause
        case resume
        case state
    }

    /// Starts a SpeakSwiftly runtime.
    ///
    /// - Parameters:
    ///   - configuration: Optional startup configuration for backend selection
    ///     and text normalization.
    ///   - stateRootURL: Optional runtime state directory. When omitted,
    ///     SpeakSwiftly uses the platform Application Support default unless a
    ///     process-level compatibility override is set.
    /// - Returns: A live ``Runtime`` that owns request submission, playback, and stored resources.
    public static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil,
        stateRootURL: URL? = nil,
    ) async -> Runtime {
        await Runtime.liftoff(configuration: configuration, stateRootURL: stateRootURL)
    }
}

// MARK: - Internal Compatibility

typealias SpeechJobType = SpeakSwiftly.SpeechJobType
typealias WorkerQueueType = SpeakSwiftly.QueueType
typealias PlaybackAction = SpeakSwiftly.PlaybackAction
typealias PlaybackState = SpeakSwiftly.PlaybackState
typealias WorkerRequestStreamEvent = SpeakSwiftly.RequestEvent
typealias WorkerRequestHandle = SpeakSwiftly.RequestHandle
typealias WorkerRuntime = SpeakSwiftly.Runtime
typealias SpeechTextDeepTraceFeatures = SpeakSwiftly.DeepTrace.Features
typealias SpeechTextDeepTraceSection = SpeakSwiftly.DeepTrace.Section
typealias SpeechTextDeepTraceSectionWindow = SpeakSwiftly.DeepTrace.SectionWindow
typealias WorkerStatusStage = SpeakSwiftly.RuntimeState
typealias WorkerRequestEventName = SpeakSwiftly.RequestEventName
typealias WorkerProgressStage = SpeakSwiftly.ProgressStage
typealias WorkerQueuedReason = SpeakSwiftly.QueuedReason
typealias WorkerStatusEvent = SpeakSwiftly.WorkerStatusEvent
typealias WorkerQueuedEvent = SpeakSwiftly.QueuedEvent
typealias WorkerStartedEvent = SpeakSwiftly.StartedEvent
typealias WorkerProgressEvent = SpeakSwiftly.ProgressEvent
typealias WorkerSuccessResponse = SpeakSwiftly.Success
typealias PlaybackStateSummary = SpeakSwiftly.WorkerPlaybackStateSnapshot
typealias ActiveWorkerRequestSummary = SpeakSwiftly.ActiveRequest
typealias QueuedWorkerRequestSummary = SpeakSwiftly.QueuedRequest
typealias WorkerFailureResponse = SpeakSwiftly.Failure
typealias WorkerErrorCode = SpeakSwiftly.ErrorCode
typealias WorkerError = SpeakSwiftly.Error
typealias ProfileSummary = SpeakSwiftly.ProfileSummary
