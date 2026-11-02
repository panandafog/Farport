import FarportCore
import FarportSessions
import FarportSSH
import Foundation
#if DEBUG
import FarportDemo
#endif

extension MobileLibraryModel {
    static func makeApplication() -> MobileLibraryModel {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        if environment["HARBOR_ISOLATED_TESTS"] == "1" {
            return isolated(hosts: [])
        }
        if DemoCatalog.isRequested(arguments: arguments, environment: environment) {
            let trust = ServerTrustModel(secrets: DemoSecretStore())
            let live = SSHConnectionProvider(hostKeyVerifier: trust.verifier)
            let model = MobileLibraryModel(repository: DemoHostRepository(),
                                           workspaceRepository: DemoWorkspaceRepository(),
                                           trust: trust, provider: DemoConnectionProvider(publicProvider: live))
            ScreenshotSupport.prepare(model)
            return model
        }
        // Simulator-only fixture: never imports a real user's library or bypasses host-key verification.
        #if targetEnvironment(simulator)
        if let port = environment["HARBOR_TEST_PORT"].flatMap(Int.init), (1...65535).contains(port) {
            let host = SavedHost(profile: HostProfile(name: "SSH fixture", hostname: "127.0.0.1", port: port,
                                                      username: "harbor", terminalResumeStrategy: .tmux),
                                 credentials: HostCredentials(password: "harbor-test"))
            return isolated(hosts: [host])
        }
        #endif
        #endif
        return live()
    }

    #if DEBUG
    static func isolated(hosts: [SavedHost], provider: (any ConnectionProvider)? = nil) -> MobileLibraryModel {
        MobileLibraryModel(repository: DebugHostRepository(hosts), workspaceRepository: DebugWorkspaceRepository(),
                           trust: ServerTrustModel(secrets: DebugSecretStore()), provider: provider)
    }
    #endif
}

#if DEBUG
final class DebugHostRepository: HostRepository {
    var hosts: [SavedHost]
    init(_ hosts: [SavedHost]) { self.hosts = hosts }
    func load() -> [SavedHost] { hosts }
    func save(_ hosts: [SavedHost]) { self.hosts = hosts }
}

final class DebugWorkspaceRepository: WorkspaceRepository {
    var snapshot = WorkspaceSnapshot()
    func load() -> WorkspaceSnapshot { snapshot }
    func save(_ snapshot: WorkspaceSnapshot) { self.snapshot = snapshot }
}

final class DebugSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func data(for account: String) -> Data? { lock.withLock { items[account] } }
    func insert(_ data: Data, for account: String) throws {
        try lock.withLock {
            guard items[account] == nil else { throw HarborError.message("Duplicate test key") }
            items[account] = data
        }
    }
    func remove(_ account: String) { _ = lock.withLock { items.removeValue(forKey: account) } }
    func remove(_ account: String, matching expected: Data) throws {
        try lock.withLock {
            guard items[account] == expected else { throw HarborError.message("Test key changed") }
            items.removeValue(forKey: account)
        }
    }
}

#endif
