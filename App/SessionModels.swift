import AppKit
import FarportCloud
import FarportCore
import FarportLocalization
import FarportSessions

typealias ConnectionRequirement = FarportSessions.ConnectionRequirement
typealias FilesModel = FarportSessions.FilesModel
typealias ServerTrustModel = FarportSessions.ServerTrustModel
typealias CloudSyncModel = FarportSessions.CloudSyncModel
typealias WorkspaceModel = SessionWorkspace<TerminalModel>

extension SessionWorkspace where Terminal == TerminalModel {
    convenience init(host: SavedHost, provider: any ConnectionProvider, snapshot: HostWorkspace? = nil,
                     routeSummary: String? = nil, trust: ServerTrustModel? = nil) {
        self.init(host: host, provider: provider, snapshot: snapshot, routeSummary: routeSummary, trust: trust) {
            TerminalModel(host: $0, provider: $1, sessionID: $2, trust: $3)
        }
    }
}

extension CloudSyncModel {
    convenience init(url: URL, containerIdentifier: String) {
        guard containerIdentifier.hasPrefix("iCloud.") else {
            self.init(unavailableReason: L10n.text("iCloud is not enabled in this local development build."))
            return
        }
        let (stream, continuation) = AsyncStream<HostSyncSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        do {
            let service = try CloudHostSync(url: url, containerIdentifier: containerIdentifier) {
                continuation.yield($0)
            }
            self.init(service: service, updates: stream) { NSApplication.shared.registerForRemoteNotifications() }
        } catch {
            self.init(unavailableReason: L10n.text("Cannot load iCloud sync state. The file was kept. %@",
                                                  error.localizedDescription))
        }
    }
}
