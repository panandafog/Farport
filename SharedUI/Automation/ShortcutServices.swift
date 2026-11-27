import FarportCore
import FarportLocalization
import FarportSSH
import Foundation

enum ShortcutServices {
    static func library() throws -> ProtectedHostRepository {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        guard environment["HARBOR_ISOLATED_TESTS"] != "1",
              environment["HARBOR_TEST_PORT"] == nil,
              !arguments.contains("--demo"), !arguments.contains("--screenshot-scene"),
              !arguments.contains(where: { $0.hasPrefix("--screenshot-scene=") }),
              !arguments.contains("--host-library") else {
            throw HarborError.message(L10n.text("Shortcuts are unavailable in demo and isolated test modes."))
        }
        #endif
        let root = URL.applicationSupportDirectory.appendingPathComponent("Harbor", isDirectory: true)
        return ProtectedHostRepository(url: root.appendingPathComponent("hosts.json"), secrets: AppSecretStore())
    }

    static func run(hostID: UUID, request: RemoteCommandRequest) async throws -> RemoteCommandResult {
        try request.validate()
        #if os(iOS)
        guard request.timeout <= 25 else {
            throw HarborError.message(L10n.text(
                "On iPhone and iPad, Shortcuts commands have a 25-second maximum timeout."
            ))
        }
        #endif
        let route = try library().automationRoute(to: hostID)
        guard let host = route.hosts.last else { throw CancellationError() }
        let pins = KnownHostRepository(secrets: AppSecretStore())
        let runner = SSHCommandRunner(hosts: route.hosts, hostKeyVerifier: { endpoint, key in
            try pins.verify(endpoint, key: key)
        })
        do { return try await runner.execute(request, on: host) } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HarborError.message(L10n.text(
                "SSH action for '%@' failed. %@ Open Farport to review credentials, server keys and network access.",
                host.profile.displayName, error.localizedDescription
            ))
        }
    }
}
