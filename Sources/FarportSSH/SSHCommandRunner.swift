import Citadel
import FarportCore
import FarportLocalization
import Foundation
import NIO

/// One command, one independent route, no PTY/tmux/startup shims and no automatic replay.
public struct SSHCommandRunner: RemoteCommandExecuting {
    private let connector: SSHRouteConnector

    public init(hosts: [SavedHost], hostKeyVerifier: @escaping HostKeyVerifier) {
        connector = SSHRouteConnector(hosts: hosts, hostKeyVerifier: hostKeyVerifier)
    }

    public func execute(_ request: RemoteCommandRequest, on host: SavedHost) async throws -> RemoteCommandResult {
        try request.validate()
        try host.validate()
        guard host.profile.terminalProvider == "ssh" else {
            throw TerminalConnectionError.configuration(L10n.text("Unsupported terminal protocol."))
        }
        let execution = CommandExecution(connector: connector)
        let operation = Task { try await execution.run(request, host: host) }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(request.timeout)) } catch { return }
            operation.cancel()
        }
        defer { deadline.cancel() }
        do {
            return try await withTaskCancellationHandler {
                let result = try await operation.value
                try Task.checkCancellation()
                return result
            } onCancel: { operation.cancel() }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if operation.isCancelled { throw RemoteCommandError.timedOut }
            throw error
        }
    }
}

private actor CommandExecution {
    let connector: SSHRouteConnector
    private var connection: SSHConnection?
    init(connector: SSHRouteConnector) { self.connector = connector }

    func run(_ request: RemoteCommandRequest, host: SavedHost) async throws -> RemoteCommandResult {
        let start = Date()
        return try await withTaskCancellationHandler {
            do {
                connection = try await connector.connect(host)
                try Task.checkCancellation()
                guard let connection else { throw CancellationError() }
                let result = try await connection.client.executeCommandResult(
                    SSHCommandPlan.command(request), input: ByteBuffer(string: request.input)
                )
                try Task.checkCancellation()
                let output = RemoteCommandResult(stdout: String(buffer: result.stdout),
                                                 stderr: String(buffer: result.stderr), exitCode: result.exitCode,
                                                 duration: Date().timeIntervalSince(start))
                await close()
                return output
            } catch {
                await close()
                if Task.isCancelled { throw CancellationError() }
                if error is SSHClient.MissingCommandExitStatus { throw RemoteCommandError.completionUnknown }
                if let failure = error as? CitadelError, case .commandOutputTooLarge = failure {
                    throw RemoteCommandError.outputTooLarge
                }
                throw SSHFailure.connection(error)
            }
        } onCancel: { Task { await self.close() } }
    }

    private func close() async {
        let current = connection
        connection = nil
        await current?.close()
    }
}

enum SSHCommandPlan {
    static func command(_ request: RemoteCommandRequest) -> String {
        let directory = request.directory.isEmpty ? "" : "cd -- \(quote(request.directory)) || exit $?; "
        return "exec /bin/sh -c " + quote(directory + "exec /bin/sh -c " + quote(request.command))
    }

    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
