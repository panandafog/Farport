import AppIntents
import FarportCore
import Foundation

/// Shortcuts carries these values between actions. Farport never persists a result/history database.
struct SSHCommandResultEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("SSH Command Result", table: "AppIntents")
    )
    @Property(title: LocalizedStringResource("Standard Output", table: "AppIntents")) var stdout: String
    @Property(title: LocalizedStringResource("Standard Error", table: "AppIntents")) var stderr: String
    @Property(title: LocalizedStringResource("Exit Code", table: "AppIntents")) var exitCode: Int
    @Property(title: LocalizedStringResource("Succeeded", table: "AppIntents")) var succeeded: Bool
    @Property(title: LocalizedStringResource("Duration (seconds)", table: "AppIntents")) var duration: Double
    @Property(title: LocalizedStringResource("Host Name", table: "AppIntents")) var hostName: String

    init() { stdout = ""; stderr = ""; exitCode = 0; succeeded = true; duration = 0; hostName = "" }
    init(_ result: RemoteCommandResult, hostName: String) {
        stdout = result.stdout; stderr = result.stderr; exitCode = result.exitCode
        succeeded = result.succeeded; duration = result.duration; self.hostName = hostName
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(hostName)", subtitle: "\(exitCode)")
    }
    var result: RemoteCommandResult {
        RemoteCommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode, duration: duration)
    }
}
