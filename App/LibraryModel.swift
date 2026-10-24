import FarportCore
import FarportLocalization
import FarportSSH
import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var hosts: [SavedHost] = []
    @Published var selection: UUID? { didSet { persistWorkspace() } }
    @Published var editor: SavedHost? { didSet { if editor == nil { cloud?.reconsiderChanges() } } }
    @Published var error: String?
    @Published var query = ""
    let finder: FinderModel?
    let trust: ServerTrustModel?
    let cloud: CloudSyncModel?
    let repository: any HostRepository
    private let workspaceRepository: any WorkspaceRepository
    private let provider: (any ConnectionProvider)?
    private var workspaces: [UUID: WorkspaceModel] = [:]
    private(set) var loadFailed = false
    private var workspaceLoadFailed = false
    private var ready = false

    init(repository: any HostRepository, workspaceRepository: any WorkspaceRepository,
         provider: (any ConnectionProvider)? = nil, finder: FinderModel? = nil, trust: ServerTrustModel? = nil,
         cloud: CloudSyncModel? = nil) {
        self.repository = repository
        self.workspaceRepository = workspaceRepository
        self.provider = provider
        self.finder = finder
        self.trust = trust
        self.cloud = cloud
        do {
            hosts = try repository.load()
        } catch {
            loadFailed = true
            self.error = L10n.text("Could not load the host library. %@", error.localizedDescription)
        }
        var saved = WorkspaceSnapshot()
        do {
            saved = try workspaceRepository.load()
            try saved.validate()
        } catch {
            workspaceLoadFailed = true
            self.error = L10n.text("Could not restore the workspace. The saved file will not be overwritten. %@",
                                   error.localizedDescription)
        }
        for host in hosts {
            installWorkspace(for: host, snapshot: saved.hosts.first { $0.hostID == host.id })
        }
        selection = hosts.contains { $0.id == saved.selectedHostID } ? saved.selectedHostID : hosts.first?.id
        ready = true
        if !loadFailed { cloud?.attach(self) }
    }

    var selectedWorkspace: WorkspaceModel? { selection.flatMap { workspaces[$0] } }

    var filteredHosts: [SavedHost] {
        hosts.filter {
            query.isEmpty || ($0.profile.displayName + " " + $0.profile.address).localizedCaseInsensitiveContains(query)
        }
    }

    private func installWorkspace(for host: SavedHost, snapshot: HostWorkspace? = nil) {
        let route = try? ConnectionRoute(to: host, library: hosts)
        let names = route?.hosts.dropLast().map { $0.profile.displayName }
        let summary = host.profile.jumpHostIDs.isEmpty ? nil :
            names.map { L10n.text("via %@", $0.joined(separator: " > ")) } ?? L10n.text("ProxyJump route unavailable")
        let provider = connectionProvider()
        if let workspace = workspaces[host.id] {
            workspace.reconfigure(host: host, provider: provider, routeSummary: summary)
            return
        }
        let workspace = WorkspaceModel(host: host, provider: provider,
                                       snapshot: snapshot, routeSummary: summary, trust: trust)
        workspace.changed = { [weak self] in self?.persistWorkspace() }
        workspaces[host.id] = workspace
    }

    private func connectionProvider() -> any ConnectionProvider {
        if let provider { return provider }
        if let trust { return SSHConnectionProvider(hosts: hosts, hostKeyVerifier: trust.verifier) }
        return SSHConnectionProvider(hosts: hosts)
    }

    func save(_ host: SavedHost) throws {
        guard !loadFailed else {
            throw HarborError.message(L10n.text("Resolve the host library read error before saving changes."))
        }
        try host.profile.validate()
        if host.credentialsConfigured { try host.validate() }
        var updated = hosts
        if let index = updated.firstIndex(where: { $0.id == host.id }) {
            updated[index] = host
        } else {
            updated.append(host)
        }
        let affected = Set((hosts + updated).filter {
            $0.id == host.id || ConnectionRoute.depends($0, on: host.id, library: hosts) ||
                ConnectionRoute.depends($0, on: host.id, library: updated)
        }.map(\.id))
        for candidate in updated where affected.contains(candidate.id) {
            _ = try ConnectionRoute(to: candidate, library: updated)
        }
        try finder?.revoke(hostIDs: affected)
        try repository.save(updated)
        replaceWorkspaces(with: updated, affected: affected)
        selection = host.id
        cloud?.localChanged()
        editor = nil
    }

    func delete(_ host: SavedHost) {
        guard !loadFailed else { return }
        do {
            let dependents = hosts.filter { ConnectionRoute.depends($0, on: host.id, library: hosts) }
            guard dependents.isEmpty else {
                throw HarborError.message(L10n.text(
                    "This jump host is used by: %@. Change their connection routes before deleting it.",
                    dependents.map { $0.profile.displayName }.joined(separator: ", ")
                ))
            }
            let updated = hosts.filter { $0.id != host.id }
            try finder?.revoke(hostIDs: [host.id])
            try repository.save(updated)
            workspaces.removeValue(forKey: host.id)?.close()
            hosts = updated
            if selection == host.id { selection = hosts.first?.id } else { persistWorkspace() }
            cloud?.localChanged()
        } catch { self.error = error.localizedDescription }
    }

    func replaceWorkspaces(with updated: [SavedHost], affected: Set<UUID>) {
        hosts = updated
        for host in updated where affected.contains(host.id) {
            installWorkspace(for: host)
        }
    }

    func persistWorkspace() {
        guard ready, !loadFailed, !workspaceLoadFailed else { return }
        let snapshot = WorkspaceSnapshot(selectedHostID: selection,
                                         hosts: hosts.compactMap { workspaces[$0.id]?.snapshot })
        do { try workspaceRepository.save(snapshot) } catch { self.error = error.localizedDescription }
    }

    func hasActiveWorkspace(_ id: UUID) -> Bool { workspaces[id]?.hasActiveSessions == true }

    func removeDeletedWorkspaces(keeping ids: Set<UUID>) {
        for id in Set(workspaces.keys).subtracting(ids) { workspaces.removeValue(forKey: id)?.close() }
    }

    func closeAll() {
        persistWorkspace()
        workspaces.values.forEach { $0.close() }
    }

    func systemWillSleep() { workspaces.values.forEach { $0.suspend() } }
    func systemDidWake() { workspaces.values.forEach { $0.resume() } }
}
