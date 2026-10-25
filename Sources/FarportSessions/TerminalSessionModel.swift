import Combine
import FarportCore
import FarportLocalization
import Foundation

@MainActor
open class TerminalSessionModel: NSObject, ObservableObject {
    public enum State: String {
        case disconnected = "Disconnected", connecting = "Connecting", connected = "Connected"
        case reconnecting = "Reconnecting", checking = "Checking connection", suspended = "Sleeping"
        case waitingForAccess = "Waiting for Local Network"

        public var label: String { L10n.text(rawValue) }
    }
    @Published public private(set) var state = State.disconnected
    @Published public private(set) var title = L10n.text("Terminal")
    @Published public private(set) var endedAt: Date?
    @Published public private(set) var endReason = ""
    @Published public private(set) var hasConnected = false
    @Published public private(set) var retryAttempt = 0
    @Published public private(set) var nextRetryAt: Date?
    @Published public var error: String?
    @Published public private(set) var settingsHostID: UUID?
    @Published public private(set) var requirement: ConnectionRequirement?
    private let output: any TerminalOutput
    public let sessionID: UUID
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

    public var usesTmux: Bool { host.profile.terminalResumeStrategy == .tmux }
    public var sessionLabel: String { usesTmux ? "harbor-" + sessionID.uuidString.lowercased() : "" }
    public var maximumRetries: Int { policy.retryDelays.count }
    public var connectLabel: String {
        if usesTmux { return L10n.text("Attach") }
        return hasConnected ? L10n.text("Reconnect") : L10n.text("Connect")
    }
    public var disconnectLabel: String { usesTmux ? L10n.text("Detach") : L10n.text("Disconnect") }

    private enum Input { case bytes(Data), resize(TerminalSize) }

    public func send(_ data: Data) {
        guard state == .connected else { return }
        input?.yield(.bytes(data))
    }

    public func resize(_ size: TerminalSize) {
        self.size = size
        if state == .connected { input?.yield(.resize(size)) }
    }

    public func updateTitle(_ title: String) { self.title = title }

    public init(host: SavedHost, provider: any ConnectionProvider, policy: ConnectionRecoveryPolicy = .init(),
                sessionID: UUID? = nil, trust: ServerTrustModel? = nil, output: any TerminalOutput) {
        self.host = host
        self.sessionID = sessionID ?? host.id
        self.provider = provider
        self.policy = policy
        self.trust = trust
        self.output = output
        super.init()
        output.setCursorVisible(false)
    }

    public func connect() {
        guard state == .disconnected else { return }
        connectionWanted = true
        retryAttempt = 0
        error = nil
        settingsHostID = nil
        requirement = nil
        endedAt = nil
        endReason = ""
        if isSleeping { state = .suspended } else { beginAttempt(recovering: false) }
    }

    public func reconfigure(host: SavedHost, provider: any ConnectionProvider) {
        let wasActive = state != .disconnected
        disconnect()
        error = nil
        settingsHostID = nil
        if wasActive { endReason = L10n.text("Connection settings changed") }
        self.host = host
        self.provider = provider
    }

    private func beginAttempt(recovering: Bool) {
        let token = UUID()
        generation = token
        state = recovering ? .reconnecting : .connecting
        nextRetryAt = nil
        if !recovering {
            output.write(Data(("\r\n" + L10n.text("Connecting to %@...", host.profile.address) + "\r\n").utf8))
        }
        connectionTask = Task {
            do {
                let connection = try await openTerminal(token: token, recovering: recovering)
                guard token == generation, !Task.isCancelled else { await connection.close(); return }
                session = connection
                startInput(connection, token: token)
                await run(connection, token: token)
                await connection.close()
            } catch {
                endConnection(token, reason: L10n.text("Connection failed"), error: error,
                              recover: isRecoverable(error))
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
            endConnection(token, reason: usesTmux ? L10n.text("Disconnected from tmux") : L10n.text("Session ended"))
        } catch {
            endConnection(token, reason: L10n.text("Connection lost"), error: error, recover: isRecoverable(error))
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
                endConnection(token, reason: L10n.text("Connection lost"), error: error, recover: isRecoverable(error))
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
        settingsHostID = (error as? TerminalConnectionError)?.settingsHostID(fallback: host.id)
        output.setCursorVisible(false)
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
            endReason = L10n.text("Reconnect attempts exhausted")
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
        title = L10n.text("Terminal")
        if isSleeping { state = .suspended; return }
        markConnected()
        startHeartbeat(token: token)
        output.focus()
    }

    private func markConnected() {
        state = .connected
        error = nil
        endedAt = nil
        endReason = ""
        nextRetryAt = nil
        output.setCursorVisible(true)
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
                    endConnection(token, reason: L10n.text("Connection lost"), error: error,
                                  recover: isRecoverable(error))
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
        output.write(data)
    }

    public func disconnect() {
        connectionWanted = false
        requirement = nil
        guard state != .disconnected else { generation = UUID(); return }
        let reason = usesTmux ? L10n.text("Detached from tmux") : L10n.text("Disconnected by user")
        let connecting = state == .connecting || state == .waitingForAccess
        endConnection(generation, reason: connecting ? L10n.text("Connection cancelled") : reason)
    }

}

extension TerminalSessionModel {
    public func suspend(disconnectTransport: Bool = false) {
        isSleeping = true
        guard state != .disconnected else { return }
        if disconnectTransport {
            endConnection(generation, reason: L10n.text("Connection closed in background"), recover: usesTmux)
            return
        }
        heartbeatTask?.cancel()
        heartbeatID = UUID()
        if session == nil {
            generation = UUID()
            connectionTask?.cancel()
            retryTask?.cancel()
        }
        nextRetryAt = nil
        state = .suspended
        output.setCursorVisible(false)
    }

    public func resume() {
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

extension TerminalSessionModel {
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

    public func reviewRequirement() {
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
