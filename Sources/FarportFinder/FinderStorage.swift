#if os(macOS)
import FarportCore
import FarportSecurity
import FarportSSH
import FileProvider
import Foundation

public enum FinderStorage {
    public static var groupIdentifier: String? { Bundle.main.object(forInfoDictionaryKey: "HarborAppGroup") as? String }

    public static func container() throws -> URL {
        guard let groupIdentifier, !groupIdentifier.contains("$("), let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw HarborError.message(
                "Finder requires Farport and its extension to be signed with the shared App Group."
            )
        }
        return url.appendingPathComponent("Finder", isDirectory: true)
    }

    public static func repository(migrateLegacy: Bool = false) throws -> ProtectedFinderLocationRepository {
        ProtectedFinderLocationRepository(
            directory: try container().appendingPathComponent("Connections", isDirectory: true),
            secrets: try KeychainSecretStore.shared(), migrateLegacy: migrateLegacy
        )
    }

    public static func reader(for domain: NSFileProviderDomain) throws -> FinderRemoteReader {
        guard let id = UUID(uuidString: domain.identifier.rawValue) else { throw FinderReadError.disabled }
        let repository = try repository()
        let location: FinderLocation
        do { location = try repository.load(id) } catch CocoaError.fileReadNoSuchFile {
            throw FinderReadError.disabled
        }
        let catalog = try container().appendingPathComponent("Indexes/" + id.uuidString + "/catalog.json")
        let knownHosts = KnownHostRepository(secrets: try KeychainSecretStore.shared())
        return try FinderRemoteReader(rootPath: location.rootPath, catalogURL: catalog,
                                      writable: location.access == .readWrite) {
            // Reload before every connection: deleting the configuration revokes network access.
            let fresh: FinderLocation
            do { fresh = try repository.load(id) } catch CocoaError.fileReadNoSuchFile {
                throw FinderReadError.disabled
            } catch { throw TerminalConnectionError.configuration(error.localizedDescription) }
            guard fresh == location, let host = fresh.host else { throw FinderReadError.disabled }
            return try await SSHConnectionProvider(hosts: fresh.hosts, hostKeyVerifier: { endpoint, key in
                try knownHosts.verify(endpoint, key: key)
            }).files(for: host)
        }
    }

    public static func isWritable(_ domain: NSFileProviderDomain) -> Bool {
        guard let id = UUID(uuidString: domain.identifier.rawValue),
              let location = try? repository().load(id) else { return false }
        return location.access == .readWrite
    }
}
#endif
