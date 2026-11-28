import AppIntents
import FarportCore
import Foundation

struct RunSSHCommandIntent: AppIntent {
    static let title = LocalizedStringResource("Run SSH Command", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource(
        """
        Run a script using a separate SSH connection. Returns output, errors and exit code. \
        No automatic retries.
        """,
        table: "AppIntents"
    ))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: LocalizedStringResource("Host", table: "AppIntents")) var host: ShortcutHost
    @Parameter(title: LocalizedStringResource("Command or Script", table: "AppIntents")) var command: String
    @Parameter(title: LocalizedStringResource("Working Directory", table: "AppIntents")) var directory: String?
    @Parameter(title: LocalizedStringResource("Standard Input", table: "AppIntents")) var input: String?
    @Parameter(title: LocalizedStringResource("Timeout (seconds)", table: "AppIntents"), default: 20)
    var timeout: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command) on \(\.$host)", table: "AppIntents") {
            \.$directory
            \.$input
            \.$timeout
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<SSHCommandResultEntity> {
        let result = try await ShortcutServices.run(hostID: host.id, request: RemoteCommandRequest(
            command: command, directory: directory ?? "", input: input ?? "", timeout: TimeInterval(timeout)
        ))
        return .result(value: SSHCommandResultEntity(result, hostName: host.name))
    }
}

struct FindSSHHostsIntent: AppIntent {
    static let title = LocalizedStringResource("Find Saved Hosts", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource(
        """
        Find hosts by name, address or username. Leave the filter empty to return all hosts. \
        Use Repeat with Each to run a command on several hosts.
        """, table: "AppIntents"
    ))
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: LocalizedStringResource("Filter", table: "AppIntents")) var filter: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Find hosts matching \(\.$filter)", table: "AppIntents")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[ShortcutHost]> {
        .result(value: try await ShortcutHostQuery().entities(matching: filter ?? ""))
    }
}
