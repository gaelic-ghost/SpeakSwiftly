import Foundation
import Network

public struct NetworkAudioDestination: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let endpoint: NetworkAudioEndpoint
    public let capabilities: NetworkAudioCapabilities
    public let lastSeen: Date

    public init(
        id: String,
        name: String,
        endpoint: NetworkAudioEndpoint,
        capabilities: NetworkAudioCapabilities,
        lastSeen: Date,
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.capabilities = capabilities
        self.lastSeen = lastSeen
    }
}

public enum NetworkAudioDestinationBrowserState: Sendable, Equatable {
    case idle
    case browsing
    case waiting(message: String)
    case failed(message: String)
}

public actor NetworkAudioDestinationBrowser {
    public private(set) var state: NetworkAudioDestinationBrowserState = .idle

    private let serviceType: String
    private let domain: String?
    private let queue: DispatchQueue
    private var browser: NWBrowser?
    private var destinations = [String: NetworkAudioDestination]()
    private var continuations = [UUID: AsyncStream<[NetworkAudioDestination]>.Continuation]()

    public init(
        serviceType: String = NetworkAudioBonjour.serviceType,
        domain: String? = nil,
        queue: DispatchQueue = DispatchQueue(label: "SpeakSwiftly.NetworkAudioDestinationBrowser"),
    ) {
        self.serviceType = serviceType
        self.domain = domain
        self.queue = queue
    }

    public func start() {
        guard browser == nil else {
            return
        }

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: domain),
            using: .tcp,
        )
        browser.browseResultsChangedHandler = { [weak browser] results, _ in
            guard browser != nil else {
                return
            }

            Task {
                await self.replaceDestinations(with: results)
            }
        }
        browser.stateUpdateHandler = { state in
            Task {
                await self.updateState(from: state)
            }
        }
        self.browser = browser
        updateState(from: .setup)
        browser.start(queue: queue)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        destinations.removeAll()
        updateState(from: .cancelled)
        publishSnapshot()
    }

    public func snapshot() -> [NetworkAudioDestination] {
        sortedDestinations()
    }

    public func updates() -> AsyncStream<[NetworkAudioDestination]> {
        let id = UUID()
        let initialSnapshot = sortedDestinations()
        let stream = AsyncStream<[NetworkAudioDestination]>.makeStream()
        continuations[id] = stream.continuation
        stream.continuation.yield(initialSnapshot)
        stream.continuation.onTermination = { _ in
            Task {
                await self.removeContinuation(id)
            }
        }
        return stream.stream
    }

    private func replaceDestinations(with results: Set<NWBrowser.Result>) {
        destinations = Dictionary(
            uniqueKeysWithValues: results.compactMap { result in
                guard let destination = NetworkAudioDestination(result: result) else {
                    return nil
                }

                return (destination.id, destination)
            },
        )
        publishSnapshot()
    }

    private func updateState(from browserState: NWBrowser.State) {
        switch browserState {
            case .setup:
                state = .idle
            case .ready:
                state = .browsing
            case let .waiting(error):
                state = .waiting(message: "Bonjour audio receiver discovery is waiting for the network to become available: \(error)")
            case let .failed(error):
                state = .failed(message: "Bonjour audio receiver discovery failed: \(error)")
            case .cancelled:
                state = .idle
            @unknown default:
                state = .failed(message: "Bonjour audio receiver discovery entered an unknown Network.framework browser state.")
        }
    }

    private func publishSnapshot() {
        let snapshot = sortedDestinations()
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func sortedDestinations() -> [NetworkAudioDestination] {
        destinations.values.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

public extension NetworkAudioDestination {
    init?(result: NWBrowser.Result, now: Date = Date()) {
        guard case let .service(name, type, domain, _) = result.endpoint else {
            return nil
        }

        let capabilities = switch result.metadata {
            case let .bonjour(txtRecord):
                NetworkAudioCapabilities(txtRecord: txtRecord)
            default:
                NetworkAudioCapabilities()
        }

        self.init(
            id: "\(name).\(type).\(domain)",
            name: name,
            endpoint: .bonjourService(name: name, type: type, domain: domain),
            capabilities: capabilities,
            lastSeen: now,
        )
    }
}
