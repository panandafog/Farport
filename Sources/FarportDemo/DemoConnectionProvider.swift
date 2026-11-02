#if DEBUG
import FarportCore
import FarportLocalization
import Foundation

/// Fictional hosts stay offline. Only the three explicit public catalog entries can use live transport.
public struct DemoConnectionProvider: ConnectionProvider {
    private let storage = DemoStorage()
    private let publicProvider: (any ConnectionProvider)?
    public init(publicProvider: (any ConnectionProvider)? = nil) { self.publicProvider = publicProvider }
    public func terminal(for host: SavedHost, sessionID: UUID) async throws -> any TerminalSession {
        if let provider = try liveProvider(for: host) {
            guard host.id != DemoCatalog.sftpOnlyHostID else {
                throw HarborError.message(L10n.text("This public server is SFTP-only. Open Files on macOS."))
            }
            return try await provider.terminal(for: host, sessionID: sessionID)
        }
        return DemoTerminalSession(host: host.profile, sessionID: sessionID)
    }
    public func files(for host: SavedHost) async throws -> any RemoteFileSession {
        if let provider = try liveProvider(for: host) { return try await provider.files(for: host) }
        return await storage.files(for: host.id)
    }
    public func waitForAccess(for host: SavedHost) async -> Bool {
        guard let provider = try? liveProvider(for: host) else { return false }
        return await provider.waitForAccess(for: host)
    }

    private func liveProvider(for host: SavedHost) throws -> (any ConnectionProvider)? {
        guard let original = DemoCatalog.publicHosts.first(where: { $0.id == host.id }) else { return nil }
        // Tab metadata, names and notes may change; endpoint/auth/route must stay exactly as published.
        var profile = host.profile
        profile.name = original.profile.name
        profile.notes = original.profile.notes
        guard profile.hasSameSettings(as: original.profile), host.credentials == original.credentials,
              host.credentialsConfigured, let publicProvider else {
            throw HarborError.message(L10n.text("Public demo settings changed. Restart the demo to restore them."))
        }
        return publicProvider
    }
}

private actor DemoStorage {
    private var sessions: [UUID: DemoFileSession] = [:]
    func files(for host: UUID) -> DemoFileSession {
        if let session = sessions[host] { return session }
        let session = DemoFileSession()
        sessions[host] = session
        return session
    }
}
#endif
