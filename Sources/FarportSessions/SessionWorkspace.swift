import Combine
import FarportCore
import FarportLocalization
import Foundation

@MainActor
public final class SessionWorkspace<Terminal: TerminalSessionModel>: ObservableObject {
    public typealias Mode = WorkspaceMode
    @Published public private(set) var host: SavedHost
    public let files: FilesModel
    @Published public private(set) var routeSummary: String?
    @Published public private(set) var tabs: [TerminalTab]
    @Published public var selectedTerminalID: UUID? { didSet { changed?() } }
    @Published public var mode: Mode { didSet { changed?() } }
    public var changed: (() -> Void)?
    private var provider: any ConnectionProvider
    private var terminals: [UUID: Terminal] = [:]
    private let trust: ServerTrustModel?
    private let makeTerminal: (SavedHost, any ConnectionProvider, UUID, ServerTrustModel?) -> Terminal
    public var hasActiveSessions: Bool {
        files.connected || files.busy || files.requirement != nil || terminals.values.contains {
            $0.state != .disconnected || $0.requirement != nil
        }
    }

    public init(host: SavedHost, provider: any ConnectionProvider, snapshot: HostWorkspace? = nil,
                routeSummary: String? = nil, trust: ServerTrustModel? = nil,
                makeTerminal: @escaping (SavedHost, any ConnectionProvider, UUID, ServerTrustModel?) -> Terminal) {
        self.makeTerminal = makeTerminal
        self.host = host
        self.routeSummary = routeSummary
        self.provider = provider
        self.trust = trust
        files = FilesModel(host: host, provider: provider, trust: trust)
        let saved = snapshot ?? HostWorkspace(hostID: host.id)
        tabs = saved.terminals
        selectedTerminalID = saved.selectedTerminalID
        mode = saved.mode
    }

    public var terminal: Terminal? {
        guard let id = selectedTerminalID, tabs.contains(where: { $0.id == id }) else { return nil }
        if let terminal = terminals[id] { return terminal }
        let terminal = makeTerminal(host, provider, id, trust)
        terminals[id] = terminal
        return terminal
    }

    public var snapshot: HostWorkspace {
        var saved = HostWorkspace(hostID: host.id)
        saved.terminals = tabs
        saved.selectedTerminalID = selectedTerminalID
        saved.mode = mode
        return saved
    }

    public func reconfigure(host: SavedHost, provider: any ConnectionProvider, routeSummary: String?) {
        terminals.values.forEach { $0.reconfigure(host: host, provider: provider) }
        files.reconfigure(host: host, provider: provider)
        self.host = host
        self.provider = provider
        self.routeSummary = routeSummary
    }

    @discardableResult
    public func addTerminal() -> UUID {
        let titles = Set(tabs.map(\.title))
        var number = 1
        while titles.contains(L10n.text("Terminal %lld", number)) { number += 1 }
        let tab = TerminalTab(title: L10n.text("Terminal %lld", number))
        terminals[tab.id] = makeTerminal(host, provider, tab.id, trust)
        tabs.append(tab)
        selectedTerminalID = tab.id
        mode = .terminal
        return tab.id
    }

    public func closeTerminal(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        terminals.removeValue(forKey: id)?.disconnect()
        tabs.remove(at: index)
        if selectedTerminalID == id {
            selectedTerminalID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        } else {
            changed?()
        }
    }

    public func renameTerminal(_ id: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = String(name.prefix(80))
        changed?()
    }

    public func selectNextTerminal(offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == selectedTerminalID } ?? 0
        let wrapped = (index + offset % tabs.count + tabs.count) % tabs.count
        selectedTerminalID = tabs[wrapped].id
    }

    public func close() {
        terminals.values.forEach { $0.disconnect() }
        files.disconnect()
    }

    public func suspend(disconnectTransport: Bool = false) {
        terminals.values.forEach { $0.suspend(disconnectTransport: disconnectTransport) }
    }
    public func resume() { terminals.values.forEach { $0.resume() } }
}
