import FarportCore
import FarportLocalization
import Foundation

extension HostLibraryModel {
    public func canApplySyncedProfiles(_ profiles: [HostProfile]) -> Bool {
        let changed = changedHostIDs(profiles)
        return editor == nil && !changed.contains { hasActiveWorkspace($0) } &&
            integration?.canApplyChanges(to: changed) != false && profiles.allSatisfy {
                storedWorkspace($0.id)?.canApplyTerminalTabs($0.terminalTabs) != false
            }
    }

    public func applySyncedProfiles(_ profiles: [HostProfile]) throws {
        guard !loadFailed, editor == nil else {
            throw HarborError.message(L10n.text("Close the host editor before applying sync."))
        }
        let updated = try SyncedProfileImport.apply(profiles, to: hosts)
        let definitions = profiles.map { profile -> HostWorkspace in
            var workspace = HostWorkspace(hostID: profile.id)
            workspace.terminals = profile.terminalTabs?.tabs ?? workspace.terminals
            workspace.selectedTerminalID = workspace.terminals.first?.id
            return workspace
        }
        try WorkspaceSnapshot(hosts: definitions).validate()
        let affected = changedHostIDs(profiles)
        try integration?.revoke(hostIDs: affected)
        try repository.save(updated)
        removeDeletedWorkspaces(keeping: Set(updated.map(\.id)))
        replaceWorkspaces(with: updated, affected: affected)
        if !hosts.contains(where: { $0.id == selection }) { selection = hosts.first?.id } else { persistWorkspace() }
    }

    private func changedHostIDs(_ profiles: [HostProfile]) -> Set<UUID> {
        let updated = profiles.map { SavedHost(profile: $0) }
        let changed = Set((hosts.map(\.profile) + profiles).filter { profile in
            guard let local = hosts.first(where: { $0.id == profile.id })?.profile,
                  let remote = profiles.first(where: { $0.id == profile.id }) else { return true }
            return !local.hasSameSettings(as: remote)
        }.map(\.id))
        return Set((hosts + updated).filter { host in
            changed.contains(host.id) || changed.contains { id in
                ConnectionRoute.depends(host, on: id, library: hosts) ||
                    ConnectionRoute.depends(host, on: id, library: updated)
            }
        }.map(\.id))
    }
}
