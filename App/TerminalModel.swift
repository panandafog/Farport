import AppKit
import FarportCore
import SwiftTerm
import SwiftUI

@MainActor
final class TerminalModel: NSObject, ObservableObject {
    enum State: String {
        case disconnected = "Disconnected", connecting = "Connecting", connected = "Connected"
        case reconnecting = "Reconnecting", checking = "Checking connection", suspended = "Sleeping"
        case waitingForAccess = "Waiting for Local Network"
    }
    @Published private(set) var state = State.disconnected
    @Published private(set) var title = "Terminal"
    @Published private(set) var endedAt: Date?
    @Published private(set) var endReason = ""
    @Published private(set) var hasConnected = false
    @Published private(set) var retryAttempt = 0
    @Published private(set) var nextRetryAt: Date?
    @Published var error: String?
    @Published private(set) var requirement: ConnectionRequirement?
    let view: SystemTerminalView
    let sessionID: UUID
    private var host: SavedHost
    private var provider: any ConnectionProvider
    private let policy: ConnectionRecoveryPolicy
    private let trust: ServerTrustModel?
    private var session: (any TerminalSession)?
    private var connectionTask: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var input: AsyncStream<Input>.Continuation?
    private var generation = UUID()
    private var heartbeatID = UUID()
    private var size = TerminalSize()
    private var connectionWanted = false
    private var isSleeping = false

    var usesTmux: Bool { host.profile.terminalResumeStrategy == .tmux }
    var sessionLabel: String { usesTmux ? "harbor-" + sessionID.uuidString.lowercased() : "" }
    var maximumRetries: Int { policy.retryDelays.count }
    var connectLabel: String { usesTmux ? "Attach" : hasConnected ? "Reconnect" : "Connect" }
    var disconnectLabel: String { usesTmux ? "Detach" : "Disconnect" }

    private enum Input { case bytes(Data), resize(TerminalSize) }

    init(host: SavedHost, provider: any ConnectionProvider, policy: ConnectionRecoveryPolicy = .init(),
         sessionID: UUID? = nil, trust: ServerTrustModel? = nil) {
        self.host = host
        self.sessionID = sessionID ?? host.id
        self.provider = provider
        self.policy = policy
        self.trust = trust
        view = SystemTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 540))
        super.init()
        view.terminalDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.applySystemTheme()
        view.getTerminal().hideCursor()
    }

    func connect() {
        guard state == .disconnected else { return }
        connectionWanted = true
        retryAttempt = 0
        error = nil
        requirement = nil
        endedAt = nil
        endReason = ""
        if isSleeping { state = .suspended } else { beginAttempt(recovering: false) }
    }

    func reconfigure(host: SavedHost, provider: any ConnectionProvider) {
        let wasActive = state != .disconnected
        disconnect()
        if wasActive { endReason = "Connection settings changed" }
        self.host = host
        self.provider = provider
    }

    private func beginAttempt(recovering: Bool) {
        let token = UUID()
        generation = token
        state = recovering ? .reconnecting : .connecting
        nextRetryAt = nil
        if !recovering { view.feed(text: "\r\nConnecting to \(host.profile.address)...\r\n") }
        connectionTask = Task {
            do {
                let connection = try await openTerminal(token: token, recovering: recovering)
                guard token == generation, !Task.isCancelled else { await connection.close(); return }
                session = connection
                startInput(connection, token: token)
                await run(connection, token: token)
                await connection.close()
            } catch {
                endConnection(token, reason: "Connection failed", error: error, recover: isRecoverable(error))
            }
        }
    }

    private func run(_ connection: any TerminalSession, token: UUID) async {
        do {
            try await connection.run(size: size, onReady: { [weak self] in
                await self?.didConnect(token)
            }, onOutput: { [weak self] data in
                await self?.receive(data, token: token)
            })
            endConnection(token, reason: usesTmux ? "Disconnected from tmux" : "Session ended")
        } catch {
            endConnection(token, reason: "Connection lost", error: error, recover: isRecoverable(error))
        }
    }

    private func startInput(_ connection: any TerminalSession, token: UUID) {
        let stream = AsyncStream<Input> { input = $0 }
        inputTask = Task {
            do {
                for await event in stream {
                    try Task.checkCancellation()
                    guard token == generation, state == .connected else { continue }
                    switch event {
                    case .bytes(let data): try await connection.send(data)
                    case .resize(let size): try await connection.resize(size)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                endConnection(token, reason: "Connection lost", error: error, recover: isRecoverable(error))
                await connection.close()
            }
        }
    }

    private func endConnection(_ token: UUID, reason: String, error: Error? = nil, recover: Bool = false) {
        guard token == generation else { return }
        let previous = session
        generation = UUID()
        cancelTasks()
        session = nil
        nextRetryAt = nil
        requirement = error.flatMap(ConnectionRequirement.init)
        endReason = requirement?.title ?? reason
        endedAt = requirement == nil ? Date() : nil
        self.error = requirement == nil ? error?.localizedDescription : nil
        view.getTerminal().hideCursor()
        let resume = usesTmux && connectionWanted && hasConnected && recover
        connectionWanted = resume
        state = resume && isSleeping ? .suspended : .disconnected
        if resume && !isSleeping { scheduleRetry() }
        if case .serverKey = requirement { reviewRequirement() }
        Task { await previous?.close() }
    }

    private func cancelTasks() {
        input?.finish()
        input = nil
        inputTask?.cancel()
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        retryTask?.cancel()
        heartbeatID = UUID()
    }

    private func scheduleRetry(immediate: Bool = false) {
        guard retryAttempt < maximumRetries else {
            connectionWanted = false
            state = .disconnected
            endReason = "Reconnect attempts exhausted"
            return
        }
        let delay = immediate ? 0 : policy.retryDelays[retryAttempt]
        retryAttempt += 1
        state = .reconnecting
        nextRetryAt = Date().addingTimeInterval(delay)
        let token = generation
        retryTask = Task {
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard token == generation, connectionWanted, !isSleeping else { return }
            beginAttempt(recovering: true)
        }
    }

    private func didConnect(_ token: UUID) {
        guard token == generation else { return }
        hasConnected = true
        title = "Terminal"
        if isSleeping { state = .suspended; return }
        markConnected()
        startHeartbeat(token: token)
        view.window?.makeFirstResponder(view)
    }

    private func markConnected() {
        state = .connected
        error = nil
        endedAt = nil
        endReason = ""
        nextRetryAt = nil
        view.getTerminal().showCursor()
        input?.yield(.resize(size))
    }

    private func startHeartbeat(token: UUID, immediate: Bool = false) {
        heartbeatTask?.cancel()
        let identity = UUID()
        heartbeatID = identity
        guard let connection = session else { return }
        heartbeatTask = Task {
            var checkNow = immediate
            while !Task.isCancelled {
                do {
                    if !checkNow { try await Task.sleep(for: .seconds(policy.heartbeatInterval)) }
                    checkNow = false
                    try await connection.checkConnection(timeout: policy.heartbeatTimeout)
                } catch {
                    guard !Task.isCancelled, token == generation, identity == heartbeatID else { return }
                    endConnection(token, reason: "Connection lost", error: error, recover: isRecoverable(error))
                    return
                }
                guard !Task.isCancelled, token == generation, identity == heartbeatID, !isSleeping else { return }
                // Reset the retry budget only after a round trip, not a briefly opened connection.
                retryAttempt = 0
                if state == .checking { markConnected() }
            }
        }
    }

    private func isRecoverable(_ error: Error) -> Bool {
        (error as? TerminalConnectionError)?.allowsReconnect == true
    }

    private func receive(_ data: Data, token: UUID) {
        guard token == generation else { return }
        view.feed(byteArray: Array(data)[...])
    }

    func disconnect() {
        connectionWanted = false
        requirement = nil
        guard state != .disconnected else { generation = UUID(); return }
        let reason = usesTmux ? "Detached from tmux" : "Disconnected by user"
        let connecting = state == .connecting || state == .waitingForAccess
        endConnection(generation, reason: connecting ? "Connection cancelled" : reason)
    }

    func systemWillSleep() {
        isSleeping = true
        guard state != .disconnected else { return }
        heartbeatTask?.cancel()
        heartbeatID = UUID()
        if session == nil {
            generation = UUID()
            connectionTask?.cancel()
            retryTask?.cancel()
        }
        nextRetryAt = nil
        state = .suspended
        view.getTerminal().hideCursor()
    }

    func systemDidWake() {
        isSleeping = false
        guard state == .suspended else { return }
        if session != nil {
            state = .checking
            startHeartbeat(token: generation, immediate: true)
        } else if usesTmux, connectionWanted {
            retryAttempt = 0
            scheduleRetry(immediate: true)
        } else {
            connectionWanted = false
            state = .disconnected
        }
    }
}

extension TerminalModel {
    private func openTerminal(token: UUID, recovering: Bool) async throws -> any TerminalSession {
        do { return try await provider.terminal(for: host, sessionID: sessionID) } catch {
            guard !recovering, token == generation, !Task.isCancelled,
                  (error as? TerminalConnectionError)?.requiresLocalNetworkPermission == true else { throw error }
            state = .waitingForAccess
            let available = await provider.waitForAccess(for: host)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            guard available else { throw error }
            state = .connecting
            return try await provider.terminal(for: host, sessionID: sessionID)
        }
    }

    func reviewRequirement() {
        guard let requirement else { return }
        if case .serverKey(let key) = requirement {
            let token = generation
            trust?.present(key, retry: { [weak self] in
                guard let self, self.generation == token else { return }
                self.connect()
            })
        } else { connect() }
    }
}

extension TerminalModel: @preconcurrency TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard state == .connected else { return }
        input?.yield(.bytes(Data(data)))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        size = TerminalSize(columns: newCols, rows: newRows)
        if state == .connected { input?.yield(.resize(size)) }
    }

    func setTerminalTitle(source: TerminalView, title: String) { self.title = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func bell(source: TerminalView) { NSSound.beep() }
    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

struct TerminalSurface: NSViewRepresentable {
    let model: TerminalModel
    func makeNSView(context: Context) -> TerminalView { model.view }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
