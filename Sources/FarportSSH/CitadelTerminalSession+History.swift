import Citadel
import FarportCore
import FarportLocalization
import Foundation

extension CitadelTerminalSession: TerminalHistorySession {
    func captureHistory() async throws -> String {
        guard !closed, writer != nil, receivedTerminalOutput, let command = launch.historyCommand() else {
            throw HarborError.message(L10n.text("tmux history is not ready. Wait for the terminal to connect."))
        }
        // Cancelling the exec stream closes only that channel, never the interactive PTY/transport.
        let operation = Task { try await readHistory(command) }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            operation.cancel()
        }
        defer { deadline.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: { operation.cancel() }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if operation.isCancelled {
                throw HarborError.message(L10n.text(
                    "Reading tmux history timed out. Try again or export Farport History."
                ))
            }
            if let failure = error as? SSHClient.CommandFailed {
                throw HarborError.message(L10n.text(
                    "Could not read tmux history (exit status %lld). " +
                    "Check that the session and its active pane still exist.", Int64(failure.exitCode)
                ))
            }
            throw error
        }
    }

    private func readHistory(_ command: String) async throws -> String {
        try Task.checkCancellation()
        var data = Data()
        var received = 0
        var oversized = false
        try await client.withExec(command) { output, _ in
            for try await chunk in output {
                try Task.checkCancellation()
                let buffer = switch chunk {
                case .stdout(let value), .stderr(let value): value
                }
                if !oversized {
                    received += buffer.readableBytes
                    oversized = received > 16 * 1_024 * 1_024
                    if !oversized, case .stdout = chunk { data.append(contentsOf: buffer.readableBytesView) }
                }
            }
            try Task.checkCancellation()
            // Discard excess bytes until EOF under the same deadline. Closing a still-streaming
            // SSH child abruptly can make some peers tear down the shared transport.
            if oversized {
                throw HarborError.message(L10n.text("tmux history exceeds the 16 MB export limit."))
            }
        }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard let text = String(data: data, encoding: .utf8) else {
            throw HarborError.message(L10n.text("tmux history is not valid UTF-8 text."))
        }
        return text
    }
}
