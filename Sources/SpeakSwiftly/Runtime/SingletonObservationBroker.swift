import Foundation

struct SingletonObservationBroker<Update: Sendable> {
    private(set) var sequence = 0
    private(set) var latestUpdate: Update?
    private var continuations = [UUID: AsyncStream<Update>.Continuation]()

    mutating func makeUpdate(
        advanceSequence: Bool = true,
        _ build: (Int) -> Update,
    ) -> Update {
        if advanceSequence {
            sequence += 1
        }
        let update = build(sequence)
        if advanceSequence {
            latestUpdate = update
        }
        return update
    }

    mutating func subscribe(
        id: UUID,
        continuation: AsyncStream<Update>.Continuation,
    ) {
        continuations[id] = continuation
    }

    mutating func removeSubscriber(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    func broadcast(_ update: Update) {
        continuations.values.forEach { continuation in
            continuation.yield(update)
        }
    }
}
