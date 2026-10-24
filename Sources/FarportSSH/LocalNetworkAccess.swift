import Foundation
#if canImport(Network)
import Network
#endif

enum LocalNetworkAccess {
    enum Event: Equatable, Sendable { case available, denied, retry, unavailable }

    // BSD sockets report EHOSTUNREACH for multiple causes. Only Network's path reason proves a privacy denial.
    static func denied(host: String, port: Int) async -> Bool {
        await probe(host: host, port: port, timeout: 1, waitingForAccess: false) == .denied
    }

    static func waitForAccess(host: String, port: Int, timeout: TimeInterval = 30) async -> Bool {
        let event = await probe(host: host, port: port, timeout: timeout, waitingForAccess: true)
        return event == .available || event == .retry
    }

    static func result(from stream: AsyncStream<Event>, waitingForAccess: Bool) async -> Event {
        for await event in stream {
            guard !Task.isCancelled else { return .unavailable }
            if waitingForAccess, event == .denied { continue }
            return event
        }
        return .unavailable
    }

    private static func probe(host: String, port: Int, timeout: TimeInterval, waitingForAccess: Bool) async -> Event {
        #if canImport(Network)
        guard !Task.isCancelled, let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return .unavailable
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "dev.harbor.local-network-check")
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        return await withTaskCancellationHandler {
            defer {
                continuation.finish()
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .waiting:
                    let denied = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
                    continuation.yield(denied ? .denied : .retry)
                    if !denied { continuation.finish() }
                case .ready:
                    continuation.yield(.available)
                    continuation.finish()
                case .failed:
                    // A refusal/DNS failure after the grant must surface through a fresh real SSH attempt.
                    continuation.yield(.retry)
                    continuation.finish()
                case .cancelled: continuation.finish()
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + max(0.01, timeout)) {
                continuation.yield(.unavailable)
                continuation.finish()
            }
            return await result(from: stream, waitingForAccess: waitingForAccess)
        } onCancel: {
            connection.cancel()
            continuation.finish()
        }
        #else
        return .unavailable
        #endif
    }
}
