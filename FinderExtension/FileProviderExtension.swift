import FarportCore
import FarportFinder
import FileProvider
import UniformTypeIdentifiers

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let reader: Result<FinderRemoteReader, Error>
    private let writable: Bool
    private var polling: Task<Void, Never>?
    private let signalSystem: Bool

    required convenience init(domain: NSFileProviderDomain) {
        self.init(domain: domain, reader: Result { try FinderStorage.reader(for: domain) },
                  writable: FinderStorage.isWritable(domain), signalSystem: true)
    }

    init(domain: NSFileProviderDomain, reader: Result<FinderRemoteReader, Error>, writable: Bool,
         signalSystem: Bool = false) {
        self.domain = domain
        self.reader = reader
        self.writable = writable
        self.signalSystem = signalSystem
        super.init()
        if signalSystem, case .success = reader {
            polling = Task { [domain] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30))
                        try await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
                    } catch is CancellationError { break } catch { /* Retry on the next bounded polling interval. */ }
                }
            }
        }
    }

    func invalidate() { polling?.cancel(); polling = nil }

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        run { [reader, domain, writable] _ in
            do {
                let item = try await reader.get().item(FinderProviderItem.coreIdentifier(identifier))
                completionHandler(FinderProviderItem(item, rootName: domain.displayName, writable: writable), nil)
            } catch { completionHandler(nil, FinderProviderError.translate(error)) }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        run { [reader, domain, writable] progress in
            var temporary: URL?
            do {
                guard let manager = NSFileProviderManager(for: domain) else { throw FinderReadError.disabled }
                let url = try manager.temporaryDirectoryURL().appendingPathComponent(UUID().uuidString)
                temporary = url
                let item = try await reader.get().download(
                    FinderProviderItem.coreIdentifier(itemIdentifier), version: version?.contentVersion, to: url
                ) { completed, total in
                    progress.totalUnitCount = Int64(clamping: total)
                    progress.completedUnitCount = Int64(clamping: completed)
                }
                try Task.checkCancellation()
                completionHandler(url, FinderProviderItem(item, rootName: domain.displayName, writable: writable), nil)
            } catch {
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                completionHandler(nil, nil, FinderProviderError.translate(error))
            }
        }
    }

    // Required File Provider protocol signature.
    // swiftlint:disable:next function_parameter_count
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        guard writable else {
            completionHandler(nil, [], false, FinderProviderError.readOnly)
            return Progress()
        }
        return run { [self] progress in
            do {
                guard let type = itemTemplate.contentType,
                      !type.conforms(to: .symbolicLink), !type.conforms(to: .aliasFile) else {
                    throw FinderWriteError.unsupportedItem
                }
                let request = FinderCreateRequest(token: itemTemplate.itemIdentifier.rawValue,
                    parentIdentifier: FinderProviderItem.coreIdentifier(itemTemplate.parentItemIdentifier),
                    name: itemTemplate.filename, isDirectory: itemTemplate.contentType == .folder, contents: url,
                    mayAlreadyExist: options.contains(.mayAlreadyExist))
                let item = try await reader.get().create(request, progress: transferProgress(progress))
                let value = item.map { FinderProviderItem($0, rootName: domain.displayName, writable: writable) }
                signalChanges()
                completionHandler(value, fields.subtracting(supportedFields), false, nil)
            } catch { completionHandler(nil, [], false, FinderProviderError.translate(error)) }
        }
    }

    // Required File Provider protocol signature.
    // swiftlint:disable:next function_parameter_count
    func modifyItem(_ item: NSFileProviderItem, baseVersion: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        guard writable else {
            completionHandler(nil, [], false, FinderProviderError.readOnly)
            return Progress()
        }
        return run { [self] progress in
            do {
                if changedFields.contains(.contents), newContents == nil { throw FinderWriteError.unsupportedItem }
                let request = FinderModifyRequest(identifier: FinderProviderItem.coreIdentifier(item.itemIdentifier),
                    baseVersion: baseVersion.contentVersion,
                    name: changedFields.contains(.filename) ? item.filename : nil,
                    parentIdentifier: changedFields.contains(.parentItemIdentifier) ?
                        FinderProviderItem.coreIdentifier(item.parentItemIdentifier) : nil,
                    contents: changedFields.contains(.contents) ? newContents : nil)
                let result = try await reader.get().modify(request, progress: transferProgress(progress))
                signalChanges()
                completionHandler(FinderProviderItem(result.item, rootName: domain.displayName, writable: writable),
                                  changedFields.subtracting(supportedFields), result.refetchContents, nil)
            } catch { completionHandler(nil, [], false, FinderProviderError.translate(error)) }
        }
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions, request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        guard writable else { completionHandler(FinderProviderError.readOnly); return Progress() }
        return run { [self] _ in
            do {
                try await reader.get().delete(FinderProviderItem.coreIdentifier(identifier),
                                               baseVersion: baseVersion.contentVersion)
                signalChanges()
                completionHandler(nil)
            } catch { completionHandler(FinderProviderError.translate(error)) }
        }
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        guard containerItemIdentifier != .trashContainer else { throw CocoaError(.featureUnsupported) }
        return FinderEnumerator(container: containerItemIdentifier, reader: try reader.get(),
                                rootName: domain.displayName, writable: writable)
    }

    private func run(_ operation: @escaping (Progress) async -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let task = Task { await operation(progress) }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    private var supportedFields: NSFileProviderItemFields { [.filename, .parentItemIdentifier, .contents] }

    private func transferProgress(_ progress: Progress) -> TransferProgress {
        { completed, total in
            progress.totalUnitCount = Int64(clamping: total)
            progress.completedUnitCount = Int64(clamping: completed)
        }
    }

    private func signalChanges() {
        guard signalSystem else { return }
        Task {
            try? await NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet)
            try? await NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer)
        }
    }
}
