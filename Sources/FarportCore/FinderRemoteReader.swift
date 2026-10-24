import FarportLocalization
import Foundation

public actor FinderRemoteReader {
    public typealias SessionFactory = @Sendable () async throws -> any RemoteFileSession
    let rootPath: String
    let catalogURL: URL
    let factory: SessionFactory
    let writable: Bool
    var catalog: FinderCatalog
    private let gate = FinderOperationGate()
    private var pollOffset = 0

    public init(rootPath: String, catalogURL: URL, writable: Bool = false, factory: @escaping SessionFactory) throws {
        try FinderPath.validateRoot(rootPath)
        self.rootPath = rootPath
        self.catalogURL = catalogURL
        self.factory = factory
        self.writable = writable
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            var saved = try JSONDecoder().decode(FinderCatalog.self, from: Data(contentsOf: catalogURL))
            guard (1...2).contains(saved.schemaVersion), saved.rootPath == rootPath else {
                throw HarborError.message(L10n.text(
                    "Unsupported Finder index. Disconnect and reconnect this Finder location."
                ))
            }
            let paths = saved.allItems.map(\.relativePath)
            guard Set(paths).count == paths.count, Set(saved.allItems.map(\.identifier)).count == paths.count else {
                throw HarborError.message(L10n.text(
                    "The Finder index contains duplicate paths or IDs. Reconnect this location."
                ))
            }
            saved.schemaVersion = 2
            catalog = saved
        } else {
            catalog = FinderCatalog(rootPath: rootPath)
        }
    }

    public func currentAnchor() -> Data { catalog.anchor }
    public func knownItems() -> [FinderItem] { catalog.allItems }
    public func relativePath(for identifier: String) throws -> String { try catalog.path(for: identifier) }

    public func enumerationItems(_ identifier: String) async throws -> [FinderItem] {
        try await serialized {
            if identifier == FinderPath.rootIdentifier { return try await self.listUnlocked(identifier) }
            let value = try await self.itemUnlocked(identifier)
            return value.isDirectory ? try await self.listUnlocked(identifier) : [value]
        }
    }

    public func refreshContainer(_ identifier: String) async throws { _ = try await enumerationItems(identifier) }

    public func list(_ identifier: String) async throws -> [FinderItem] {
        try await serialized { try await self.listUnlocked(identifier) }
    }

    func listUnlocked(_ identifier: String) async throws -> [FinderItem] {
        let folder = try catalog.path(for: identifier)
        let path = try FinderPath.remotePath(folder, root: rootPath)
        let entries = try await withSession { session in
            guard try await session.canonicalPath(path) == path else { throw FinderReadError.outsideRoot }
            return try await session.list(path)
        }
        try Task.checkCancellation()
        let items = try entries.filter { $0.kind != .symbolicLink }.map { entry in
            let expected = try RemotePath.appending(entry.name, to: path)
            guard entry.path == expected else { throw FinderReadError.outsideRoot }
            let relative = folder.isEmpty ? entry.name : folder + "/" + entry.name
            return try FinderItem(relativePath: relative, isDirectory: entry.kind == .directory,
                                  size: entry.size, modified: entry.modified)
        }.sorted { $0.relativePath < $1.relativePath }
        guard Set(items.map(\.relativePath)).count == items.count else { throw FinderReadError.unsupportedNames }
        var updated = catalog
        updated.reconcile(items, in: folder)
        try save(updated)
        return catalog.folders[folder] ?? []
    }

    public func item(_ identifier: String) async throws -> FinderItem {
        try await serialized { try await self.itemUnlocked(identifier) }
    }

    func itemUnlocked(_ identifier: String) async throws -> FinderItem {
        let path = try catalog.path(for: identifier)
        if path.isEmpty { return try FinderItem(relativePath: "", isDirectory: true) }
        let parent = catalog.allItems.first { $0.relativePath == FinderPath.parent(path) }?.identifier ??
            FinderPath.rootIdentifier
        let siblings = try await listUnlocked(parent)
        guard let item = siblings.first(where: { $0.identifier == identifier }) else {
            throw FinderReadError.noSuchItem
        }
        return item
    }

    public func download(_ identifier: String, version: Data?, to url: URL,
                         progress: @escaping TransferProgress) async throws -> FinderItem {
        try await serialized {
            let before = try await self.itemUnlocked(identifier)
            guard !before.isDirectory else { throw FinderReadError.noSuchItem }
            guard version == nil || version == before.contentVersion else { throw FinderReadError.versionChanged }
            let path = try FinderPath.remotePath(before.relativePath, root: self.rootPath)
            let activity = RemoteFileRequest.Activity()
            do {
                try await RemoteFileRequest.perform(activity: activity, factory: self.factory, action: { session in
                    guard try await session.canonicalPath(path) == path else { throw FinderReadError.outsideRoot }
                    try await session.download(path, to: url) { completed, total in
                        await activity.recordProgress()
                        await progress(completed, total)
                    }
                })
                let after = try await self.itemUnlocked(identifier)
                guard before.matchesMetadata(after) else { throw FinderReadError.versionChanged }
                try Task.checkCancellation()
                let item = try after.identified(after.identifier, parent: after.parentIdentifier,
                                                digest: FileDigest.sha256(url))
                var updated = self.catalog
                updated.upsert(item)
                try self.save(updated)
                return item
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
    }

    public func changes(since anchor: Data, container: String?) throws -> FinderChanges {
        try catalog.changes(since: anchor, container: container)
    }

    public func refreshKnownFolders(limit: Int = 16) async throws {
        try await serialized {
            let folders = self.catalog.folders.keys.sorted()
            guard !folders.isEmpty else { _ = try await self.listUnlocked(FinderPath.rootIdentifier); return }
            for offset in 0..<min(max(1, limit), folders.count) {
                try Task.checkCancellation()
                let folder = folders[(self.pollOffset + offset) % folders.count]
                guard self.catalog.folders[folder] != nil else { continue }
                let id = self.catalog.allItems.first { $0.relativePath == folder }?.identifier ??
                    FinderPath.rootIdentifier
                _ = try await self.listUnlocked(id)
            }
            self.pollOffset = (self.pollOffset + min(max(1, limit), folders.count)) % folders.count
        }
    }

    func serialized<T>(_ action: () async throws -> T) async throws -> T {
        try await gate.acquire()
        do {
            try Task.checkCancellation()
            try await recoverMutation()
            let result = try await action()
            await gate.release()
            return result
        } catch {
            if error is RemoteFileFailure {
                var updated = catalog
                updated.pending = nil
                try? save(updated)
            }
            await gate.release()
            throw error
        }
    }

    func save(_ updated: FinderCatalog) throws {
        try PrivateFileStorage.write(try JSONEncoder().encode(updated), to: catalogURL)
        catalog = updated
    }

    func withSession<T: Sendable>(
        _ action: @escaping @Sendable (any RemoteFileSession) async throws -> T
    ) async throws -> T {
        try await RemoteFileRequest.perform(factory: factory, action: action)
    }
}
