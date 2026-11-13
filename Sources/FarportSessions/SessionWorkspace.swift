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
        let restoredTabs = (host.profile.terminalTabs?.tabs ?? saved.terminals).map {
            $0.fillingMissingResumeStrategy(with: host.profile.terminalResumeStrategy)
        }
        tabs = restoredTabs
        selectedTerminalID = restoredTabs.contains { $0.id == saved.selectedTerminalID } ?
            saved.selectedTerminalID : restoredTabs.first?.id
        mode = saved.mode
    }

    public var terminal: Terminal? {
        guard let id = selectedTerminalID, let tab = tabs.first(where: { $0.id == id }) else { return nil }
        if let terminal = terminals[id] { return terminal }
        let terminal = makeTerminal(configuredHost(for: tab), provider, id, trust)
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
        for tab in tabs {
            terminals[tab.id]?.reconfigure(host: configuredHost(for: tab, host: host), provider: provider)
        }
        files.reconfigure(host: host, provider: provider)
        self.host = host
        self.provider = provider
        self.routeSummary = routeSummary
    }

    public func canApplyTerminalTabs(_ layout: SyncedTerminalTabs?) -> Bool {
        guard let layout else { return true }
        return !terminals.contains { id, terminal in
            let incoming = layout.tabs.first { $0.id == id }
            let changed = incoming == nil ||
                (incoming?.resumeStrategy ?? resumeStrategy(for: id)) != resumeStrategy(for: id)
            return changed && (terminal.state != .disconnected || terminal.requirement != nil)
        }
    }

    public func applyTerminalTabs(host: SavedHost) {
        let callback = changed
        changed = nil
        defer { changed = callback }
        let previousHost = self.host
        let previousTabs = tabs
        self.host = host
        guard let layout = host.profile.terminalTabs else { return }
        let updated = layout.tabs.map { tab in
            tab.fillingMissingResumeStrategy(with: previousTabs.first { $0.id == tab.id }?.resumeStrategy ??
                                              host.profile.terminalResumeStrategy)
        }
        let remaining = Set(updated.map(\.id))
        for id in Set(terminals.keys).subtracting(remaining) { terminals.removeValue(forKey: id)?.disconnect() }
        tabs = updated
        for tab in updated {
            let previous = previousTabs.first { $0.id == tab.id }
            if previous?.effectiveResumeStrategy(default: previousHost.profile.terminalResumeStrategy) !=
                tab.effectiveResumeStrategy(default: host.profile.terminalResumeStrategy) {
                terminals[tab.id]?.reconfigure(host: configuredHost(for: tab), provider: provider)
            }
        }
        if !tabs.contains(where: { $0.id == selectedTerminalID }) { selectedTerminalID = tabs.first?.id }
    }

    @discardableResult
    public func addTerminal() -> UUID {
        let titles = Set(tabs.map(\.title))
        var number = 1
        while titles.contains(L10n.text("Terminal %lld", number)) { number += 1 }
        let tab = TerminalTab(title: L10n.text("Terminal %lld", number),
                              resumeStrategy: host.profile.terminalResumeStrategy)
        terminals[tab.id] = makeTerminal(configuredHost(for: tab), provider, tab.id, trust)
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

    public func resumeStrategy(for id: UUID) -> TerminalResumeStrategy {
        tabs.first { $0.id == id }?.effectiveResumeStrategy(default: host.profile.terminalResumeStrategy) ??
            host.profile.terminalResumeStrategy
    }

    public func requiresDisconnect(for id: UUID, resumeStrategy strategy: TerminalResumeStrategy) -> Bool {
        guard resumeStrategy(for: id) != strategy,
              let terminal = terminals[id] else { return false }
        return terminal.state != .disconnected || terminal.requirement != nil
    }

    public func setResumeStrategy(_ strategy: TerminalResumeStrategy, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              tabs[index].resumeStrategy != strategy else { return }
        let previous = resumeStrategy(for: id)
        tabs[index].resumeStrategy = strategy
        if previous != resumeStrategy(for: id) {
            terminals[id]?.reconfigure(host: configuredHost(for: tabs[index]), provider: provider)
        }
        changed?()
    }

    private func configuredHost(for tab: TerminalTab, host: SavedHost? = nil) -> SavedHost {
        var configured = host ?? self.host
        configured.profile.terminalResumeStrategy = tab.effectiveResumeStrategy(
            default: configured.profile.terminalResumeStrategy
        )
        return configured
    }

    public func moveTerminals(from offsets: IndexSet, to destination: Int) {
        let updated = ItemOrdering.moving(tabs, from: offsets, to: destination)
        guard updated != tabs else { return }
        tabs = updated
        changed?()
    }

    public func moveTerminal(_ id: UUID, to target: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              let destination = tabs.firstIndex(where: { $0.id == target }) else { return }
        moveTerminals(from: IndexSet(integer: index), to: destination + (index < destination ? 1 : 0))
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
