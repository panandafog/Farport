import Citadel
import FarportCore
import FarportLocalization
import Foundation
import NIO
import NIOSSH

public struct SSHConnectionProvider: ConnectionProvider {
    private let connector: SSHRouteConnector
    var waitForNetworkAccess: @Sendable (String, Int) async -> Bool = { host, port in
        await LocalNetworkAccess.waitForAccess(host: host, port: port)
    }

    public init(hosts: [SavedHost] = [], hostKeyVerifier: @escaping HostKeyVerifier = { endpoint, key in
        throw HostKeyChallenge(endpoint: endpoint, presented: key)
    }) {
        connector = SSHRouteConnector(hosts: hosts, hostKeyVerifier: hostKeyVerifier)
    }

    public func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        guard host.profile.terminalProvider == "ssh" else {
            throw TerminalConnectionError.configuration(L10n.text("Unsupported terminal protocol."))
        }
        return CitadelTerminalSession(
            connection: try await connector.connect(host),
            launch: TerminalLaunchPlan(profile: host.profile, sessionID: sessionID)
        )
    }

    public func files(for host: SavedHost) async throws -> any RemoteFileSession {
        guard host.profile.fileProvider == "sftp" else {
            throw TerminalConnectionError.configuration(L10n.text("Unsupported file protocol."))
        }
        return CitadelFileSession(connection: try await connector.connect(host))
    }

    public func waitForAccess(for host: SavedHost) async -> Bool {
        guard !Task.isCancelled, let route = try? ConnectionRoute(to: host, library: connector.hosts),
              let first = route.hosts.first else { return false }
        return await waitForNetworkAccess(first.profile.hostname, first.profile.port)
    }
}

actor CitadelTerminalSession: TerminalSession {
    let client: SSHClient
    let connection: SSHConnection
    var writer: TTYStdinWriter?
    var closed = false
    var decorationColors: TerminalDecorationColors?
    var appliedDecorationColors: TerminalDecorationColors?
    var decorationTask: Task<Void, Never>?
    var receivedTerminalOutput = false
    let launch: TerminalLaunchPlan

    init(connection: SSHConnection, launch: TerminalLaunchPlan) {
        self.connection = connection
        client = connection.client
        self.launch = launch
    }

    func run(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
             onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        guard !closed else { throw CancellationError() }
        defer { writer = nil }
        do {
            try await runPTY(size: size, onReady: onReady, onOutput: onOutput)
            if !closed, !client.isConnected {
                throw TerminalConnectionError.transport(L10n.text("SSH transport closed."))
            }
        } catch let error as SSHClient.CommandFailed where launch.command != nil && error.exitCode == 127 {
            throw TerminalConnectionError.configuration(
                L10n.text(
                    "tmux is not installed or not available in the server's PATH. Install tmux on the " +
                    "server or select Standard SSH in the host settings."
                )
            )
        } catch let error as SSHClient.CommandFailed {
            throw TerminalConnectionError.configuration(
                L10n.text("Remote terminal exited with status %lld.", Int64(error.exitCode))
            )
        } catch {
            if closed { throw CancellationError() }
            throw SSHFailure.connection(error)
        }
    }

    private func runPTY(size: TerminalSize, onReady: @escaping @Sendable () async -> Void,
                        onOutput: @escaping @Sendable (Data) async -> Void) async throws {
        appliedDecorationColors = decorationColors
        let command = launch.command(colors: decorationColors)
        try await client.withPTY(.init(wantReply: true, term: "xterm-256color",
                                      terminalCharacterWidth: size.columns, terminalRowHeight: size.rows,
                                      terminalPixelWidth: 0, terminalPixelHeight: 0,
                                      terminalModes: .init([:])), command: command) { output, input in
            self.setWriter(input)
            await onReady()
            for try await chunk in output {
                try Task.checkCancellation()
                switch chunk {
                case .stdout(let buffer), .stderr(let buffer):
                    self.terminalOutputReceived()
                    await onOutput(Data(buffer.readableBytesView))
                }
            }
        }
    }

    private func setWriter(_ writer: TTYStdinWriter) { self.writer = writer }

    func send(_ data: Data) async throws {
        guard let writer, !closed else { throw HarborError.message(L10n.text("Terminal is disconnected.")) }
        do { try await writer.write(ByteBuffer(bytes: data)) } catch { throw SSHFailure.connection(error) }
    }

    func resize(_ size: TerminalSize) async throws {
        try await writer?.changeSize(cols: size.columns, rows: size.rows, pixelWidth: 0, pixelHeight: 0)
    }

    func checkConnection(timeout: TimeInterval) async throws {
        guard !closed else { throw CancellationError() }
        do {
            try await client.checkConnection(timeout: .milliseconds(Int64(max(0.01, timeout) * 1_000)))
        } catch { throw SSHFailure.connection(error) }
    }

    func close() async {
        guard !closed else { return }
        closed = true
        writer = nil
        decorationTask?.cancel()
        decorationTask = nil
        await connection.close()
    }
}
