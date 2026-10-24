import Foundation

extension FinderRemoteReader {
    func childPath(_ name: String, in parent: String) throws -> String {
        let path = try RemotePath.appending(name, to: parent.isEmpty ? "/" : "/" + parent)
        return String(path.dropFirst())
    }

    func validateParent(of relative: String, session: any RemoteFileSession) async throws {
        let parent = try FinderPath.remotePath(FinderPath.parent(relative), root: rootPath)
        guard try await session.canonicalPath(parent) == parent else { throw FinderReadError.outsideRoot }
    }

    func lookup(_ relative: String) async throws -> FinderItem? {
        let path = try FinderPath.remotePath(relative, root: rootPath)
        return try await withSession { session in
            try await self.validateParent(of: relative, session: session)
            let entries = try await session.list(RemotePath.parent(of: path))
            guard let entry = entries.first(where: { $0.path == path }) else { return nil }
            guard entry.kind != .symbolicLink, try await session.canonicalPath(path) == path else {
                throw FinderReadError.outsideRoot
            }
            return try FinderItem(relativePath: relative, isDirectory: entry.kind == .directory,
                                  size: entry.size, modified: entry.modified)
        }
    }

    func remoteDigest(_ relative: String) async throws -> Data {
        let scratch = catalogURL.deletingLastPathComponent().appendingPathComponent("Scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = try FinderPath.remotePath(relative, root: rootPath)
        let activity = RemoteFileRequest.Activity()
        try await RemoteFileRequest.perform(activity: activity, factory: factory, action: { session in
            try await self.validateParent(of: relative, session: session)
            guard try await session.canonicalPath(path) == path else { throw FinderReadError.outsideRoot }
            try await session.download(path, to: url) { _, _ in await activity.recordProgress() }
        })
        return try FileDigest.sha256(url)
    }

    func record(_ item: FinderItem, parent: String) async throws -> FinderItem {
        var updated = catalog
        let existing = catalog.allItems.first { $0.relativePath == item.relativePath }
        let value = try item.identified(existing?.identifier ?? UUID().uuidString, parent: parent, digest: item.digest)
        updated.upsert(value)
        try save(updated)
        return catalog.allItems.first { $0.relativePath == item.relativePath } ?? value
    }

    func prepare(_ mutation: FinderMutation) throws {
        var updated = catalog
        updated.pending = mutation
        try save(updated)
    }

    func finish(_ mutation: FinderMutation) async throws -> FinderItem {
        guard let remote = try await lookup(mutation.destination) else { throw FinderWriteError.conflict }
        var updated = catalog
        if mutation.kind == .rename {
            try updated.move(mutation.item, to: mutation.destination, parent: mutation.parentIdentifier)
        }
        let result = try remote.identified(mutation.item.identifier, parent: mutation.parentIdentifier,
                                           digest: mutation.digest)
        updated.upsert(result)
        if mutation.kind == .create {
            var receipts = updated.creationReceipts ?? [:]
            receipts[mutation.token] = result.identifier
            if receipts.count > 1_024, let key = receipts.keys.sorted().first { receipts.removeValue(forKey: key) }
            updated.creationReceipts = receipts
        }
        updated.pending = nil
        try save(updated)
        return result
    }

    func finishDeletion(_ mutation: FinderMutation) throws {
        var updated = catalog
        let parent = FinderPath.parent(mutation.item.relativePath)
        let remaining = (updated.folders[parent] ?? []).filter { $0.identifier != mutation.item.identifier }
        updated.reconcile(remaining, in: parent)
        updated.pending = nil
        try save(updated)
    }

    // A persisted intent distinguishes an acknowledged retry from an unrelated pre-existing destination.
    // Recovery observes remote state only; it never resumes a destructive operation during browsing.
    func recoverMutation() async throws {
        guard let pending = catalog.pending else { return }
        let target = try await lookup(pending.destination)
        if pending.kind == .delete {
            if target == nil { try finishDeletion(pending); return }
        } else if let target, target.isDirectory == pending.item.isDirectory {
            let contentMatches: Bool
            if let digest = pending.digest {
                contentMatches = try await remoteDigest(pending.destination) == digest
            } else {
                contentMatches = pending.kind == .create || target.matchesMetadata(pending.item)
            }
            var moved = true
            if pending.kind == .rename { moved = try await lookup(pending.item.relativePath) == nil }
            if contentMatches, moved { _ = try await finish(pending); return }
        }
        var updated = catalog
        updated.pending = nil
        try save(updated)
    }
}
