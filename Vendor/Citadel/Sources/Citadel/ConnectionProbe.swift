import NIO
import NIOConcurrencyHelpers
import NIOSSH

extension SSHClient {
    public struct ConnectionProbeTimedOut: Error {}

    /// Authenticated SSH round trip without executing a command or changing the terminal.
    /// Even OPEN_FAILURE proves the peer is responding (for example with MaxSessions=1).
    public func checkConnection(timeout: TimeAmount) async throws {
        let channel = session.channel
        let sshHandler = session.sshHandler
        try await withTaskCancellationHandler {
            try await channel.eventLoop.flatSubmit { () -> EventLoopFuture<Void> in
                guard channel.isActive else {
                    return channel.eventLoop.makeFailedFuture(ChannelError.ioOnClosedChannel)
                }
                let completed = channel.eventLoop.makePromise(of: Void.self)
                let finished = NIOLockedValueBox(false)
                let finish: @Sendable (Result<Void, Error>) -> Bool = { result in
                    let first = finished.withLockedValue { value in
                        if value { return false }
                        value = true
                        return true
                    }
                    if first { completed.completeWith(result) }
                    return first
                }
                let opening = channel.eventLoop.makePromise(of: Channel.self)
                let deadline = channel.eventLoop.scheduleTask(in: timeout) {
                    if finish(.failure(ConnectionProbeTimedOut())) { channel.close(promise: nil) }
                }
                opening.futureResult.flatMap { probe in
                    probe.close()
                }.whenComplete { result in
                    switch result {
                    case .success:
                        _ = finish(.success(()))
                    case .failure(let error as NIOSSHError) where error.type == .channelSetupRejected:
                        _ = finish(.success(()))
                    case .failure(let error):
                        _ = finish(.failure(error))
                    }
                }
                completed.futureResult.whenComplete { _ in deadline.cancel() }
                sshHandler.value.createChannel(opening) { probe, _ in
                    probe.eventLoop.makeSucceededVoidFuture()
                }
                return completed.futureResult
            }.get()
        } onCancel: {
            // Closing releases an outstanding open/close request even on a black-holed link.
            channel.close(promise: nil)
        }
    }
}
