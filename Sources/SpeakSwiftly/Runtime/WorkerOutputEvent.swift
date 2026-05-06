import Foundation

package extension SpeakSwiftly {
    enum WorkerOutputEvent {
        case status(WorkerStatusEvent)
        case queued(QueuedEvent)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case success(Success)
        case failure(Failure)
    }
}
