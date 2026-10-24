import FarportCore
import FarportLocalization
import Foundation

extension LibraryModel {
    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor", isDirectory: true)
        var libraryURL = root.appendingPathComponent("hosts.json")
        #if DEBUG
        if ProcessInfo.processInfo.environment["HARBOR_ISOLATED_TESTS"] == "1" {
            libraryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("hosts.json")
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--host-library"),
           ProcessInfo.processInfo.arguments.count > index + 1 {
            libraryURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1])
        }
        #endif
        let secrets = AppSecretStore()
        let trust = ServerTrustModel(secrets: secrets)
        let cloud = libraryURL == root.appendingPathComponent("hosts.json") ? CloudSyncModel(
            url: root.appendingPathComponent("hosts.icloud.json"),
            containerIdentifier: Bundle.main.object(forInfoDictionaryKey: "HarborCloudContainer") as? String ?? ""
        ) : nil
        self.init(repository: ProtectedHostRepository(url: libraryURL, secrets: secrets),
                  workspaceRepository: JSONWorkspaceRepository(
                    url: libraryURL.deletingPathExtension().appendingPathExtension("workspace.json")
                  ), finder: FinderModel(hostKeyVerifier: trust.verifier, trust: trust), trust: trust, cloud: cloud)
        if libraryURL == root.appendingPathComponent("hosts.json") {
            finder?.reload()
            if let issue = finder?.error { error = L10n.text("Finder migration: %@", issue) }
        }
    }
}
