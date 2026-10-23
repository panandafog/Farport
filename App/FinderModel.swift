import AppKit
import FileProvider
import HarborCore
import HarborFinder
import HarborSSH

@MainActor
final class FinderModel: ObservableObject {
    @Published private(set) var locations: [FinderLocation] = []
    @Published private(set) var busy = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private let hostKeyVerifier: HostKeyVerifier
    private let trust: ServerTrustModel?

    init(hostKeyVerifier: @escaping HostKeyVerifier, trust: ServerTrustModel? = nil) {
        self.hostKeyVerifier = hostKeyVerifier
        self.trust = trust
    }

    func reload() {
        do {
            locations = try FinderStorage.repository(migrateLegacy: true).loadAll()
        } catch { self.error = error.localizedDescription }
    }

    func connect(host: SavedHost, library: [SavedHost], folder: String, access: FinderLocation.Access = .readOnly) {
        perform {
            let provider = SSHConnectionProvider(hosts: library, hostKeyVerifier: self.hostKeyVerifier)
            let root = try await RemoteFileRequest.perform(
                factory: { try await provider.files(for: host) },
                action: { session in
                    let root = try await session.canonicalPath(folder.isEmpty ? "." : folder)
                    _ = try await session.list(root)
                    return root
                }
            )
            try Task.checkCancellation()
            let repository = try FinderStorage.repository(migrateLegacy: true)
            let existing = try repository.loadAll()
            let location = try existing.first { $0.hostID == host.id && $0.rootPath == root && $0.access == access } ??
                FinderLocation(host: host, library: library, rootPath: root, access: access)
            let previous = existing.first { $0.id == location.id }
            try repository.save(location)
            do {
                try await NSFileProviderManager.add(self.domain(location))
                try Task.checkCancellation()
            } catch {
                if Task.isCancelled {
                    try? repository.remove(location.id)
                    _ = try? await NSFileProviderManager.remove(self.domain(location),
                                                               mode: .preserveDownloadedUserData)
                } else if let previous {
                    try? repository.save(previous)
                } else {
                    try? repository.remove(location.id)
                }
                throw error
            }
            self.reload()
            try await self.reveal(location)
        }
    }

    func open(_ location: FinderLocation) { perform { try await self.reveal(location) } }

    func cancel() { task?.cancel() }

    func refresh(_ location: FinderLocation) {
        perform {
            guard let manager = NSFileProviderManager(for: self.domain(location)) else {
                throw FinderReadError.disabled
            }
            try await manager.signalEnumerator(for: .workingSet)
            try await manager.signalEnumerator(for: .rootContainer)
        }
    }

    func disconnect(_ location: FinderLocation) {
        perform {
            // Revocation is checked before every network connection, including requests from a surviving extension.
            try FinderStorage.repository().remove(location.id)
            _ = try await NSFileProviderManager.remove(self.domain(location), mode: .preserveDownloadedUserData)
            self.reload()
        }
    }

    func revoke(hostIDs: Set<UUID>) throws {
        task?.cancel()
        let repository = try FinderStorage.repository()
        let affected = try repository.loadAll().filter { location in
            location.hosts.contains { hostIDs.contains($0.id) }
        }
        for location in affected { try repository.remove(location.id) }
        reload()
        for location in affected {
            Task {
                do {
                    _ = try await NSFileProviderManager.remove(domain(location), mode: .preserveDownloadedUserData)
                } catch {
                    self.error = "Finder connection was revoked, but could not be removed. " +
                        error.localizedDescription
                }
            }
        }
    }

    private func reveal(_ location: FinderLocation) async throws {
        guard let manager = NSFileProviderManager(for: domain(location)) else { throw FinderReadError.disabled }
        let url = try await manager.getUserVisibleURL(for: .rootContainer)
        guard NSWorkspace.shared.open(url) else { throw HarborError.message("Could not open the Finder location.") }
    }

    private func domain(_ location: FinderLocation) -> NSFileProviderDomain {
        let folder = location.rootPath == "/" ? "Root" : (location.rootPath as NSString).lastPathComponent
        return NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(location.id.uuidString),
                                    displayName: location.name + " (" + folder +
                                        (location.access == .readOnly ? ", Read Only)" : ")"))
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        task = Task {
            do { try await operation() } catch is CancellationError { } catch {
                if let challenge = (error as? TerminalConnectionError)?.hostKeyChallenge, let trust {
                    trust.present(challenge)
                } else {
                    self.error = error.localizedDescription
                }
            }
            busy = false
            task = nil
        }
    }
}
