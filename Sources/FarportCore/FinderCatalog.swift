import Foundation

public struct FinderItem: Codable, Equatable, Sendable {
    public let relativePath: String
    public let isDirectory: Bool
    public let size: UInt64?
    public let modified: Date?
    public let digest: Data?
    private let persistentIdentifier: String?
    private let persistentParentIdentifier: String?
    public var identifier: String { persistentIdentifier ?? ((try? FinderPath.identifier(relativePath)) ?? "invalid") }
    public var parentIdentifier: String {
        persistentParentIdentifier ?? ((try? FinderPath.identifier(FinderPath.parent(relativePath))) ?? "invalid")
    }
    public var name: String { relativePath.split(separator: "/").last.map(String.init) ?? "Farport" }
    public var contentVersion: Data {
        if isDirectory { return Data("directory".utf8) }
        let metadata = "\(isDirectory)|\(size.map(String.init) ?? "-")|\(modified?.timeIntervalSince1970 ?? 0)"
        return Data((metadata + (digest.map { "|" + $0.base64EncodedString() } ?? "")).utf8)
    }

    public init(relativePath: String, isDirectory: Bool, size: UInt64? = nil, modified: Date? = nil,
                identifier: String? = nil, parentIdentifier: String? = nil, digest: Data? = nil) throws {
        _ = try FinderPath.identifier(relativePath)
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        persistentIdentifier = identifier
        persistentParentIdentifier = parentIdentifier
        self.digest = digest
    }

    func identified(_ identifier: String, parent: String, digest: Data? = nil) throws -> FinderItem {
        try FinderItem(relativePath: relativePath, isDirectory: isDirectory, size: size, modified: modified,
                       identifier: identifier, parentIdentifier: parent, digest: digest)
    }

    func matchesMetadata(_ other: FinderItem) -> Bool {
        isDirectory == other.isDirectory && size == other.size && modified == other.modified
    }
}

public struct FinderChanges: Sendable {
    public let updated: [FinderItem]
    public let deleted: [String]
    public let anchor: Data
}

// Only visited folders are indexed. Never walk an entire server tree for Spotlight.
struct FinderCatalog: Codable {
    struct Anchor: Codable { let epoch: UUID; let revision: Int }
    struct Change: Codable {
        let revision: Int
        let path: String
        let item: FinderItem?
        var deletedIdentifier: String?
    }

    var schemaVersion = 2
    let rootPath: String
    var epoch = UUID()
    var revision = 0
    var oldestRevision = 0
    var folders: [String: [FinderItem]] = [:]
    var journal: [Change] = []
    var retiredIdentifiers: Set<String>?
    var pending: FinderMutation?
    var creationReceipts: [String: String]?

    var anchor: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Anchor(epoch: epoch, revision: revision))) ?? Data()
    }
    var allItems: [FinderItem] { folders.values.flatMap { $0 }.sorted { $0.relativePath < $1.relativePath } }

    mutating func reconcile(_ incoming: [FinderItem], in folder: String) {
        let previous = folders[folder] ?? []
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.relativePath, $0) })
        let oldPaths = Dictionary(uniqueKeysWithValues: allItems.map { ($0.relativePath, $0.identifier) })
        let parent = allItems.first { $0.relativePath == folder }?.identifier ?? FinderPath.rootIdentifier
        let active = Dictionary(uniqueKeysWithValues: allItems.map { ($0.identifier, $0.relativePath) })
        let items = incoming.map { item -> FinderItem in
            let existing = old[item.relativePath]
            let collision = active[item.identifier].map { $0 != item.relativePath } ?? false
            let identifier = existing?.identifier ??
                (collision || retiredIdentifiers?.contains(item.identifier) == true ?
                    UUID().uuidString : item.identifier)
            let digest = existing.map { $0.matchesMetadata(item) ? $0.digest : nil } ?? nil
            return (try? item.identified(identifier, parent: parent, digest: item.digest ?? digest)) ?? item
        }
        let new = Dictionary(uniqueKeysWithValues: items.map { ($0.relativePath, $0) })
        var changes = items.filter { old[$0.relativePath] != $0 }.map { ($0.relativePath, Optional($0)) }
        for removed in previous where new[removed.relativePath] == nil ||
            new[removed.relativePath]?.isDirectory != removed.isDirectory {
            if new[removed.relativePath] == nil { changes.append((removed.relativePath, nil)) }
            for key in folders.keys.filter({ $0 == removed.relativePath || $0.hasPrefix(removed.relativePath + "/") }) {
                changes += (folders.removeValue(forKey: key) ?? []).map { ($0.relativePath, nil) }
            }
        }
        folders[folder] = items
        guard !changes.isEmpty else { return }
        revision += 1
        journal += changes.map { path, item in
            let identifier = oldPaths[path]
            if item == nil, let identifier { retiredIdentifiers = (retiredIdentifiers ?? []).union([identifier]) }
            return Change(revision: revision, path: path, item: item, deletedIdentifier: item == nil ? identifier : nil)
        }
        if journal.count > 4_000 {
            let cutoff = journal[journal.count - 2_000].revision
            journal.removeAll { $0.revision <= cutoff }
            oldestRevision = cutoff
        }
    }

    func changes(since data: Data, container: String?) throws -> FinderChanges {
        guard let anchor = try? JSONDecoder().decode(Anchor.self, from: data), anchor.epoch == epoch,
              anchor.revision >= oldestRevision, anchor.revision <= revision else {
            throw FinderReadError.anchorExpired
        }
        var latest: [String: Change] = [:]
        for change in journal where change.revision > anchor.revision {
            if let container, FinderPath.parent(change.path) != container && change.path != container { continue }
            let identifier = change.item?.identifier ?? change.deletedIdentifier ?? change.path
            latest[identifier] = change
        }
        let changes = latest.values.sorted { $0.path < $1.path }
        let deleted = changes.filter { $0.item == nil }.compactMap {
            $0.deletedIdentifier ?? (try? FinderPath.identifier($0.path))
        }
        return FinderChanges(updated: changes.compactMap(\.item), deleted: deleted,
                             anchor: self.anchor)
    }

    func path(for identifier: String) throws -> String {
        if identifier == FinderPath.rootIdentifier { return "" }
        guard let item = allItems.first(where: { $0.identifier == identifier }) else {
            throw FinderReadError.noSuchItem
        }
        return item.relativePath
    }

    mutating func upsert(_ item: FinderItem) {
        let parent = FinderPath.parent(item.relativePath)
        var items = folders[parent] ?? []
        items.removeAll { $0.identifier == item.identifier || $0.relativePath == item.relativePath }
        items.append(item)
        reconcile(items, in: parent)
    }

    mutating func move(_ item: FinderItem, to destination: String, parent: String) throws {
        let source = item.relativePath
        var result: [String: [FinderItem]] = [:]
        var updates: [FinderItem] = []
        for (folder, items) in folders {
            let renamedFolder = replacingPrefix(folder, source: source, destination: destination)
            result[renamedFolder] = try items.map { entry in
                let path = replacingPrefix(entry.relativePath, source: source, destination: destination)
                guard path != entry.relativePath else { return entry }
                let changed = try FinderItem(relativePath: path, isDirectory: entry.isDirectory,
                                             size: entry.size, modified: entry.modified, identifier: entry.identifier,
                                             parentIdentifier: entry.identifier == item.identifier ? parent :
                                                entry.parentIdentifier, digest: entry.digest)
                updates.append(changed)
                return changed
            }
        }
        let changed = try FinderItem(relativePath: destination, isDirectory: item.isDirectory,
                                     size: item.size, modified: item.modified, identifier: item.identifier,
                                     parentIdentifier: parent, digest: item.digest)
        for key in result.keys { result[key]?.removeAll { $0.identifier == item.identifier } }
        result[FinderPath.parent(destination), default: []].append(changed)
        folders = result
        revision += 1
        journal += updates.map { Change(revision: revision, path: $0.relativePath, item: $0) }
    }

    private func replacingPrefix(_ path: String, source: String, destination: String) -> String {
        path == source ? destination : path.hasPrefix(source + "/") ? destination + path.dropFirst(source.count) : path
    }
}
