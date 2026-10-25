import FarportCloud
import FarportCore
import FarportLocalization
import FarportSessions
import FarportSSH
import Foundation
import UIKit

@MainActor
final class MobileLibraryModel: HostLibraryModel<MobileTerminalModel> {
    init(repository: any HostRepository, workspaceRepository: any WorkspaceRepository,
         trust: ServerTrustModel, cloud: CloudSyncModel? = nil, provider: (any ConnectionProvider)? = nil) {
        super.init(repository: repository, workspaceRepository: workspaceRepository, trust: trust, cloud: cloud,
                   makeProvider: { hosts in
            provider ?? SSHConnectionProvider(hosts: hosts, hostKeyVerifier: trust.verifier)
        }, makeTerminal: { MobileTerminalModel(host: $0, provider: $1, sessionID: $2, trust: $3) })
    }

    static func live() -> MobileLibraryModel {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Harbor", isDirectory: true)
        let secrets = AppSecretStore()
        return MobileLibraryModel(
            repository: ProtectedHostRepository(url: root.appendingPathComponent("hosts.json"), secrets: secrets),
            workspaceRepository: JSONWorkspaceRepository(url: root.appendingPathComponent("hosts.workspace.json")),
            trust: ServerTrustModel(secrets: secrets), cloud: makeCloud(root: root)
        )
    }

    private static func makeCloud(root: URL) -> CloudSyncModel {
        let identifier = Bundle.main.object(forInfoDictionaryKey: "HarborCloudContainer") as? String ?? ""
        guard identifier.hasPrefix("iCloud.") else {
            return CloudSyncModel(unavailableReason: L10n.text(
                "iCloud is not enabled in this local development build."
            ))
        }
        let (stream, continuation) = AsyncStream<HostSyncSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        do {
            let service = try CloudHostSync(url: root.appendingPathComponent("hosts.icloud.json"),
                                            containerIdentifier: identifier) { continuation.yield($0) }
            return CloudSyncModel(service: service, updates: stream) {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            return CloudSyncModel(unavailableReason: L10n.text(
                "Cannot load iCloud sync state. The file was kept. %@", error.localizedDescription
            ))
        }
    }
}
