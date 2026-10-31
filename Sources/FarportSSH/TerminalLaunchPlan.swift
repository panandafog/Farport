import FarportCore
import Foundation

struct TerminalLaunchPlan {
    let command: String?

    init(profile: HostProfile, sessionID: UUID? = nil,
         tmuxSearchPaths: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]) {
        switch profile.terminalResumeStrategy {
        case .none:
            command = nil
        case .tmux:
            let name = "harbor-" + (sessionID ?? profile.id).uuidString.lowercased()
            // Preserve the SSH account's PATH precedence; noninteractive macOS shells
            // often omit Homebrew. Never source shell startup files to discover a binary.
            let candidates = tmuxSearchPaths.map(Self.quote).joined(separator: " ")
            let script = "tmux_binary=$(command -v tmux 2>/dev/null) || tmux_binary=; " +
                "if [ -z \"$tmux_binary\" ]; then for candidate in \(candidates); do " +
                "if [ -f \"$candidate\" ] && [ -x \"$candidate\" ]; then " +
                "tmux_binary=$candidate; break; fi; done; fi; " +
                "if [ -z \"$tmux_binary\" ]; then " +
                "printf '%s\\n' 'Farport: tmux is unavailable on this server.' >&2; exit 127; fi; " +
                "exec \"$tmux_binary\" new-session -A -s \(name) \\; set-option -t \(name) mouse on"
            // SSH runs exec requests through the account's login shell, which may not be POSIX.
            command = "exec /bin/sh -c " + Self.quote(script)
        }
    }
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
