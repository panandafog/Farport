import FarportCore
import SwiftUI

@MainActor
final class WorkspaceModel: ObservableObject {
    typealias Mode = WorkspaceMode
    @Published private(set) var host: SavedHost
    let files: FilesModel
    @Published private(set) var routeSummary: String?
    @Published private(set) var tabs: [TerminalTab]
    @Published var selectedTerminalID: UUID? { didSet { changed?() } }
    @Published var mode: Mode { didSet { changed?() } }
    var changed: (() -> Void)?
    private var provider: any ConnectionProvider
    private var terminals: [UUID: TerminalModel] = [:]
    private let trust: ServerTrustModel?
    var hasActiveSessions: Bool {
        files.connected || files.busy || files.requirement != nil || terminals.values.contains {
            $0.state != .disconnected || $0.requirement != nil
        }
    }

    init(host: SavedHost, provider: any ConnectionProvider, snapshot: HostWorkspace? = nil,
         routeSummary: String? = nil, trust: ServerTrustModel? = nil) {
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

    var terminal: TerminalModel? {
        guard let id = selectedTerminalID, tabs.contains(where: { $0.id == id }) else { return nil }
        if let terminal = terminals[id] { return terminal }
        let terminal = TerminalModel(host: host, provider: provider, sessionID: id, trust: trust)
        terminals[id] = terminal
        return terminal
    }

    var snapshot: HostWorkspace {
        var saved = HostWorkspace(hostID: host.id)
        saved.terminals = tabs
        saved.selectedTerminalID = selectedTerminalID
        saved.mode = mode
        return saved
    }

    func reconfigure(host: SavedHost, provider: any ConnectionProvider, routeSummary: String?) {
        terminals.values.forEach { $0.reconfigure(host: host, provider: provider) }
        files.reconfigure(host: host, provider: provider)
        self.host = host
        self.provider = provider
        self.routeSummary = routeSummary
    }

    @discardableResult
    func addTerminal() -> UUID {
        let titles = Set(tabs.map(\.title))
        var number = 1
        while titles.contains("Terminal \(number)") { number += 1 }
        let tab = TerminalTab(title: "Terminal \(number)")
        terminals[tab.id] = TerminalModel(host: host, provider: provider, sessionID: tab.id, trust: trust)
        tabs.append(tab)
        selectedTerminalID = tab.id
        mode = .terminal
        return tab.id
    }

    func closeTerminal(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        terminals.removeValue(forKey: id)?.disconnect()
        tabs.remove(at: index)
        if selectedTerminalID == id {
            selectedTerminalID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        } else {
            changed?()
        }
    }

    func renameTerminal(_ id: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = String(name.prefix(80))
        changed?()
    }

    func selectNextTerminal(offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == selectedTerminalID } ?? 0
        selectedTerminalID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    func close() {
        terminals.values.forEach { $0.disconnect() }
        files.disconnect()
    }

    func systemWillSleep() { terminals.values.forEach { $0.systemWillSleep() } }
    func systemDidWake() { terminals.values.forEach { $0.systemDidWake() } }
}
