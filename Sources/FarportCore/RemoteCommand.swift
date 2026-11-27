import FarportLocalization
import Foundation

public struct RemoteCommandRequest: Sendable {
    public let command: String
    public let directory: String
    public let input: String
    public let timeout: TimeInterval

    public init(command: String, directory: String = "", input: String = "", timeout: TimeInterval = 20) {
        self.command = command; self.directory = directory; self.input = input; self.timeout = timeout
    }

    public func validate() throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.contains("\0"), command.utf8.count <= 65_536 else {
            throw HarborError.message(L10n.text("Enter a command or script of up to 64 KB without null characters."))
        }
        guard !directory.contains("\0"), directory.utf8.count <= 4_096 else {
            throw HarborError.message(L10n.text(
                "Enter a working directory of up to 4096 bytes without null characters."
            ))
        }
        guard input.utf8.count <= 1_024 * 1_024 else {
            throw HarborError.message(L10n.text("Command input exceeds the 1 MB limit."))
        }
        guard timeout.isFinite, (1...300).contains(timeout) else {
            throw HarborError.message(L10n.text("Command timeout must be between 1 and 300 seconds."))
        }
    }
}

public struct RemoteCommandResult: Codable, Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public let duration: TimeInterval
    public var succeeded: Bool { exitCode == 0 }

    public init(stdout: String, stderr: String, exitCode: Int, duration: TimeInterval) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode; self.duration = duration
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public var reportText: String {
        L10n.text("Exit Code: %lld", Int64(exitCode)) + "\n\n" +
            L10n.text("Standard Output") + "\n" + stdout + "\n\n" + L10n.text("Standard Error") + "\n" + stderr
    }
}

public protocol RemoteCommandExecuting: Sendable {
    func execute(_ request: RemoteCommandRequest, on host: SavedHost) async throws -> RemoteCommandResult
}

public enum RemoteCommandError: LocalizedError, Sendable {
    case timedOut, outputTooLarge, completionUnknown

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            L10n.text("SSH command timed out. It may have run on the server. Farport did not retry it.")
        case .outputTooLarge:
            L10n.text("Command output exceeds the 4 MB limit. The command was not retried.")
        case .completionUnknown:
            L10n.text("The server did not confirm the command's exit status. It may have run. Do not retry blindly.")
        }
    }
}
