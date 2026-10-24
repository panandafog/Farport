#if os(macOS)
import CryptoKit
import FarportCore
import FileProvider
import Foundation
import UniformTypeIdentifiers

public final class FinderProviderItem: NSObject, NSFileProviderItem {
    public let value: FinderItem
    private let rootName: String
    private let writable: Bool

    public init(_ value: FinderItem, rootName: String, writable: Bool = false) {
        self.value = value
        self.rootName = rootName
        self.writable = writable
    }

    public var itemIdentifier: NSFileProviderItemIdentifier { Self.identifier(value.identifier) }
    public var parentItemIdentifier: NSFileProviderItemIdentifier { Self.identifier(value.parentIdentifier) }
    public var filename: String { value.relativePath.isEmpty ? rootName : value.name }
    public var contentType: UTType {
        value.isDirectory ? .folder : UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
    }
    public var capabilities: NSFileProviderItemCapabilities {
        var result: NSFileProviderItemCapabilities = value.isDirectory ?
            [.allowsReading, .allowsContentEnumerating] : [.allowsReading]
        guard writable else { return result }
        if value.isDirectory { result.insert(.allowsAddingSubItems) } else { result.insert(.allowsWriting) }
        if !value.relativePath.isEmpty { result.formUnion([.allowsRenaming, .allowsReparenting, .allowsDeleting]) }
        return result
    }
    public var documentSize: NSNumber? { value.size.map { NSNumber(value: $0) } }
    public var contentModificationDate: Date? { value.modified }
    public var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: value.contentVersion,
                                  metadataVersion: Data(SHA256.hash(data: Data(value.relativePath.utf8))))
    }

    public static func identifier(_ value: String) -> NSFileProviderItemIdentifier {
        value == FinderPath.rootIdentifier ? .rootContainer : NSFileProviderItemIdentifier(value)
    }

    public static func coreIdentifier(_ value: NSFileProviderItemIdentifier) -> String {
        value == .rootContainer ? FinderPath.rootIdentifier : value.rawValue
    }
}

public enum FinderProviderError {
    public static var readOnly: Error { CocoaError(.fileWriteNoPermission) }

    public static func translate(_ error: Error) -> Error {
        if error is CancellationError { return CocoaError(.userCancelled) }
        let cocoa = error as NSError
        if cocoa.domain == NSFileProviderErrorDomain || cocoa.domain == NSCocoaErrorDomain { return error }
        if let failure = error as? FinderReadError { return readFailure(failure) }
        if let failure = error as? FinderWriteError { return writeFailure(failure) }
        if let failure = error as? RemoteFileFailure { return remoteFailure(failure) }
        if let failure = error as? TerminalConnectionError, !failure.allowsReconnect {
            return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.notAuthenticated.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: failure.localizedDescription])
        }
        return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.serverUnreachable.rawValue,
                       userInfo: [NSUnderlyingErrorKey: error])
    }

    private static func remoteFailure(_ failure: RemoteFileFailure) -> Error {
        switch failure {
        case .missing: return NSFileProviderError(.noSuchItem)
        case .permissionDenied: return CocoaError(.fileWriteNoPermission)
        case .unsupported: return CocoaError(.featureUnsupported)
        case .rejected:
            return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.cannotSynchronize.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: failure.localizedDescription])
        }
    }

    private static func writeFailure(_ failure: FinderWriteError) -> Error {
        switch failure {
        case .readOnly: return readOnly
        case .unsupportedItem: return CocoaError(.featureUnsupported)
        case .collision(let item):
            return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.filenameCollision.rawValue,
                           userInfo: [NSFileProviderErrorItemKey: FinderProviderItem(item, rootName: "Farport")])
        case .directoryNotEmpty: return NSFileProviderError(.directoryNotEmpty)
        case .conflict, .unsupportedReplacement, .pendingOperation:
            let message = failure.message
            return NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.cannotSynchronize.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func readFailure(_ failure: FinderReadError) -> Error {
        switch failure {
        case .noSuchItem: return NSFileProviderError(.noSuchItem)
        case .versionChanged: return NSFileProviderError(.versionNoLongerAvailable)
        case .anchorExpired: return NSFileProviderError(.syncAnchorExpired)
        case .outsideRoot: return CocoaError(.fileReadNoPermission)
        case .disabled: return NSFileProviderError(.notAuthenticated)
        case .timedOut: return NSFileProviderError(.serverUnreachable)
        case .unsupportedNames: return CocoaError(.featureUnsupported)
        }
    }
}
#endif
