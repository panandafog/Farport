import FarportCore
import FarportFinder
import FileProvider

final class FinderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let reader: FinderRemoteReader
    private let rootName: String
    private let writable: Bool
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var invalidated = false
    private struct Cursor: Codable { let token: UUID; let offset: Int }
    private var snapshot: [FinderItem]?
    private var pageToken = UUID()
    private var nextOffset = 0

    init(container: NSFileProviderItemIdentifier, reader: FinderRemoteReader, rootName: String,
         writable: Bool = false) {
        self.container = container
        self.reader = reader
        self.rootName = rootName
        self.writable = writable
    }

    func invalidate() {
        lock.lock()
        invalidated = true
        task?.cancel()
        task = nil
        snapshot = nil
        lock.unlock()
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        start { [self] in
            do {
                var loaded: [FinderItem]?
                if isInitial(page) {
                    if container == .workingSet {
                        loaded = await reader.knownItems()
                    } else {
                        loaded = try await reader.enumerationItems(FinderProviderItem.coreIdentifier(container))
                    }
                }
                let result = try readPage(page, loaded: loaded)
                try Task.checkCancellation()
                let values = result.items.map { FinderProviderItem($0, rootName: rootName, writable: writable) }
                observer.didEnumerate(values)
                observer.finishEnumerating(upTo: result.next)
            } catch { observer.finishEnumeratingWithError(FinderProviderError.translate(error)) }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        start { [self] in
            do {
                let coreID = FinderProviderItem.coreIdentifier(container)
                let path = container == .workingSet ? nil : try await reader.relativePath(for: coreID)
                if path != nil {
                    try await reader.refreshContainer(coreID)
                } else {
                    try await reader.refreshKnownFolders()
                }
                let changes = try await reader.changes(since: anchor.rawValue, container: path)
                try Task.checkCancellation()
                observer.didDeleteItems(withIdentifiers: changes.deleted.map(FinderProviderItem.identifier))
                let values = changes.updated.map { FinderProviderItem($0, rootName: rootName, writable: writable) }
                observer.didUpdate(values)
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(changes.anchor), moreComing: false)
            } catch { observer.finishEnumeratingWithError(FinderProviderError.translate(error)) }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        Task { completionHandler(NSFileProviderSyncAnchor(await reader.currentAnchor())) }
    }

    private func start(_ operation: @escaping () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        let next = Task { await operation() }
        if invalidated { next.cancel() }
        task = next
    }

    private func isInitial(_ page: NSFileProviderPage) -> Bool {
        page.rawValue == NSFileProviderPage.initialPageSortedByName as Data ||
            page.rawValue == NSFileProviderPage.initialPageSortedByDate as Data
    }

    private func readPage(_ page: NSFileProviderPage, loaded: [FinderItem]?) throws
        -> (items: [FinderItem], next: NSFileProviderPage?) {
        lock.lock()
        defer { lock.unlock() }
        if let loaded {
            snapshot = loaded
            pageToken = UUID()
            nextOffset = 0
        } else {
            guard let cursor = try? JSONDecoder().decode(Cursor.self, from: page.rawValue),
                  cursor.token == pageToken, cursor.offset == nextOffset else {
                throw NSFileProviderError(.pageExpired)
            }
        }
        guard !invalidated, let snapshot else { throw NSFileProviderError(.pageExpired) }
        // A fixed snapshot prevents changes on the server from shifting offsets between pages.
        let end = min(nextOffset + 100, snapshot.count)
        let items = Array(snapshot[nextOffset..<end])
        nextOffset = end
        if end == snapshot.count { self.snapshot = nil; return (items, nil) }
        let cursor = Cursor(token: pageToken, offset: end)
        return (items, NSFileProviderPage(try JSONEncoder().encode(cursor)))
    }
}
