import FarportCore
import Foundation

struct TerminalLaunchPlan {
    let command: String?

    init(profile: HostProfile, sessionID: UUID? = nil) {
        switch profile.terminalResumeStrategy {
        case .none:
            command = nil
        case .tmux:
            let name = "harbor-" + (sessionID ?? profile.id).uuidString.lowercased()
            // Only a UUID-derived identifier enters the command; user labels and paths never do.
            let script = "if ! command -v tmux >/dev/null 2>&1; then " +
                "printf '%s\\n' 'Farport: tmux is unavailable on this server.' >&2; exit 127; fi; " +
                "exec tmux new-session -A -s \(name)"
            // SSH runs exec requests through the account's login shell, which may not be POSIX.
            command = "exec /bin/sh -c '" + script.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }
    }
}
