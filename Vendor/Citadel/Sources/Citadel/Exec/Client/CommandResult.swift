import NIO
import NIOConcurrencyHelpers
import NIOSSH

public struct SSHCommandResult: Sendable {
    public let stdout: ByteBuffer
    public let stderr: ByteBuffer
    public let exitCode: Int
}

extension SSHClient {
    public struct MissingCommandExitStatus: Error {}

    /// Non-PTY exec with separate bounded output and explicit stdin EOF. Nonzero exit codes are results.
    /// The caller owns the connection/deadline; cancellation closes this child, not another terminal.
    public func executeCommandResult(_ command: String, input: ByteBuffer,
                                     maximumOutputBytes: Int = 4 * 1024 * 1024) async throws -> SSHCommandResult {
        let completion = CommandCompletion(eventLoop.makePromise(of: SSHCommandResult.self))
        let active = NIOLockedValueBox<Channel?>(nil)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let channel = try await eventLoop.flatSubmit { [eventLoop, sshHandler = session.sshHandler] in
                    let opening = eventLoop.makePromise(of: Channel.self)
                    let deadline = eventLoop.scheduleTask(in: .seconds(15)) {
                        opening.fail(CitadelError.channelCreationFailed)
                    }
                    opening.futureResult.whenComplete { _ in deadline.cancel() }
                    sshHandler.value.createChannel(opening) { channel, _ in
                        channel.pipeline.addHandler(CommandResultHandler(completion: completion,
                                                                        maximumBytes: maximumOutputBytes))
                    }
                    return opening.futureResult
                }.get()
                active.withLockedValue { $0 = channel }
                do {
                    try Task.checkCancellation()
                    try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(
                        command: command, wantReply: true
                    ))
                    if input.readableBytes > 0 {
                        try await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(input)))
                    }
                    try await channel.close(mode: .output)
                } catch { completion.finish(.failure(error)) }
                do {
                    let result = try await completion.promise.futureResult.get()
                    try Task.checkCancellation()
                    if channel.isActive { try? await channel.close() }
                    return result
                } catch {
                    if channel.isActive { try? await channel.close() }
                    throw error
                }
            } catch {
                completion.finish(.failure(error))
                throw error
            }
        } onCancel: {
            completion.finish(.failure(CancellationError()))
            active.withLockedValue { $0 }?.close(promise: nil)
        }
    }
}

/// Completion may also arrive from task cancellation; buffers below remain event-loop confined.
private final class CommandCompletion: Sendable {
    let promise: EventLoopPromise<SSHCommandResult>
    private let finished = NIOLockedValueBox(false)
    init(_ promise: EventLoopPromise<SSHCommandResult>) { self.promise = promise }
    func finish(_ result: Result<SSHCommandResult, Error>) {
        let first = finished.withLockedValue { value in
            if value { return false }
            value = true
            return true
        }
        if first { promise.completeWith(result) }
    }
}

private final class CommandResultHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    private let completion: CommandCompletion
    private let maximumBytes: Int
    private var stdout = ByteBuffer()
    private var stderr = ByteBuffer()
    private var exitCode: Int?
    private var eof = false

    init(completion: CommandCompletion, maximumBytes: Int) {
        self.completion = completion; self.maximumBytes = maximumBytes
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure {
            self.completion.finish(.failure($0))
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let chunk = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = chunk.data else { return }
        guard bytes.readableBytes <= maximumBytes - stdout.readableBytes - stderr.readableBytes else {
            completion.finish(.failure(CitadelError.commandOutputTooLarge))
            context.close(promise: nil)
            return
        }
        switch chunk.type {
        case .channel: stdout.writeBuffer(&bytes)
        case .stdErr: stderr.writeBuffer(&bytes)
        default: break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus: exitCode = status.exitStatus
        case ChannelEvent.inputClosed: eof = true
        case is NIOSSH.ChannelFailureEvent:
            completion.finish(.failure(CitadelError.channelFailure))
            context.close(promise: nil)
        default: context.fireUserInboundEventTriggered(event)
        }
        if eof, exitCode != nil { finish(); context.close(promise: nil) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        completion.finish(.failure(error))
        context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) { finish(); context.fireChannelInactive() }
    func handlerRemoved(context: ChannelHandlerContext) { finish() }
    private func finish() {
        if let exitCode {
            completion.finish(.success(SSHCommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)))
        } else { completion.finish(.failure(SSHClient.MissingCommandExitStatus())) }
    }
}
