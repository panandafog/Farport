#if DEBUG
import FarportCore
import Foundation

public enum DemoCatalog {
    public static func isRequested(arguments: [String], environment: [String: String]) -> Bool {
        (arguments.contains("--demo") || DemoScreenshotScene.isRequested(in: arguments)) &&
            environment["HARBOR_ISOLATED_TESTS"] != "1"
    }

    public static var hosts: [SavedHost] {
        offlineHosts + publicHosts
    }

    public static var offlineHosts: [SavedHost] {
        zip(["Production API", "Staging", "Build Runner", "Bastion", "Raspberry Pi"],
            ["api", "staging", "build", "bastion", "pi"]).enumerated().map { index, item in
            SavedHost(profile: HostProfile(id: identifier(UInt8(index + 1)), name: item.0,
                hostname: "\(item.1).farport.example", username: "alex", initialDirectory: "/home/alex/app"))
        }
    }

    public static var workspace: WorkspaceSnapshot {
        let saved = hosts.enumerated().map { index, host in
            var workspace = HostWorkspace(hostID: host.id)
            workspace.terminals[0].title = "Shell"
            if index == 0 {
                workspace.terminals += [TerminalTab(id: identifier(20), title: "Logs"),
                                        TerminalTab(id: identifier(21), title: "Deploy")]
            }
            return workspace
        }
        return WorkspaceSnapshot(selectedHostID: hosts.first?.id, hosts: saved, deviceID: identifier(100))
    }

    static func identifier(_ value: UInt8) -> UUID {
        UUID(uuid: (0xFA, 0x52, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, value))
    }
}

public final class DemoHostRepository: HostRepository {
    private var hosts: [SavedHost]
    public init(hosts: [SavedHost] = DemoCatalog.hosts) { self.hosts = hosts }
    public func load() -> [SavedHost] { hosts }
    public func save(_ hosts: [SavedHost]) { self.hosts = hosts }
}

public final class DemoWorkspaceRepository: WorkspaceRepository {
    private var snapshot = DemoCatalog.workspace
    public init() {}
    public func load() -> WorkspaceSnapshot { snapshot }
    public func save(_ snapshot: WorkspaceSnapshot) { self.snapshot = snapshot }
}
#endif
