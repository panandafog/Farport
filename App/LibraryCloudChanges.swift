import FarportCore
import FarportLocalization
import Foundation

extension LibraryModel {
    func canApplySyncedProfiles(_ profiles: [HostProfile]) -> Bool {
        let changed = changedHostIDs(profiles)
        return editor == nil && finder?.busy != true &&
            !changed.contains { hasActiveWorkspace($0) } &&
            !(finder?.locations.contains { location in location.hosts.contains { changed.contains($0.id) } } ?? false)
    }

    func applySyncedProfiles(_ profiles: [HostProfile]) throws {
        guard !loadFailed, editor == nil else {
            throw HarborError.message(L10n.text("Close the host editor before applying sync."))
        }
        let updated = try SyncedProfileImport.apply(profiles, to: hosts)
        let affected = changedHostIDs(profiles)
        try finder?.revoke(hostIDs: affected)
        try repository.save(updated)
        removeDeletedWorkspaces(keeping: Set(updated.map(\.id)))
        replaceWorkspaces(with: updated, affected: affected)
        if !hosts.contains(where: { $0.id == selection }) { selection = hosts.first?.id } else { persistWorkspace() }
    }

    private func changedHostIDs(_ profiles: [HostProfile]) -> Set<UUID> {
        let updated = profiles.map { SavedHost(profile: $0) }
        let changed = Set((hosts.map(\.profile) + profiles).filter { profile in
            hosts.first { $0.id == profile.id }?.profile != profiles.first { $0.id == profile.id }
        }.map(\.id))
        return Set((hosts + updated).filter { host in
            changed.contains(host.id) || changed.contains { id in
                ConnectionRoute.depends(host, on: id, library: hosts) ||
                    ConnectionRoute.depends(host, on: id, library: updated)
            }
        }.map(\.id))
    }
}
