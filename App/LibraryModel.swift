import FarportCore
import FarportSessions
import FarportSSH
import Foundation

@MainActor
final class LibraryModel: HostLibraryModel<TerminalModel> {
    let finder: FinderModel?

    init(repository: any HostRepository, workspaceRepository: any WorkspaceRepository,
         provider: (any ConnectionProvider)? = nil, finder: FinderModel? = nil, trust: ServerTrustModel? = nil,
         cloud: CloudSyncModel? = nil) {
        self.finder = finder
        super.init(repository: repository, workspaceRepository: workspaceRepository, trust: trust, cloud: cloud,
                   integration: finder, makeProvider: { hosts in
            if let provider { return provider }
            if let trust { return SSHConnectionProvider(hosts: hosts, hostKeyVerifier: trust.verifier) }
            return SSHConnectionProvider(hosts: hosts)
        }, makeTerminal: { TerminalModel(host: $0, provider: $1, sessionID: $2, trust: $3) })
    }

    func systemWillSleep() { suspend() }
    func systemDidWake() { resume() }
}

extension FinderModel: HostLibraryIntegration {
    func canApplyChanges(to hostIDs: Set<UUID>) -> Bool {
        !busy && !locations.contains { location in location.hosts.contains { hostIDs.contains($0.id) } }
    }
}
