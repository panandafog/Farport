import FarportCore
import Foundation

struct TerminalLaunchPlan {
    private let launchScript: String?
    var command: String? { launchScript.map { "exec /bin/sh -c " + Self.quote($0) } }
    private let discovery: String
    private let sessionName: String?

    func command(colors: TerminalDecorationColors?) -> String? {
        guard let launchScript, let colors else { return command }
        return "exec /bin/sh -c " + Self.quote(launchScript + " \\; " + styleCommands(colors))
    }

    func decorationCommand(_ colors: TerminalDecorationColors) -> String? {
        guard sessionName != nil else { return nil }
        return "exec /bin/sh -c " + Self.quote(discovery + "exec \"$tmux_binary\" " + styleCommands(colors))
    }

    private func styleCommands(_ colors: TerminalDecorationColors) -> String {
        guard let sessionName else { return "" }
        let style = String(format: "fg=#%06x,bg=#%06x", colors.foreground, colors.background)
        return "set-option -t \(sessionName) status-style \(Self.quote(style)) \\; " +
            "set-window-option -t \(sessionName) mode-style \(Self.quote(style))"
    }

    init(profile: HostProfile, sessionID: UUID? = nil,
         tmuxSearchPaths: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]) {
        switch profile.terminalResumeStrategy {
        case .none:
            launchScript = nil
            discovery = ""
            sessionName = nil
        case .tmux:
            let name = "harbor-" + (sessionID ?? profile.id).uuidString.lowercased()
            sessionName = name
            // Preserve the SSH account's PATH precedence; noninteractive macOS shells
            // often omit Homebrew. Never source shell startup files to discover a binary.
            let candidates = tmuxSearchPaths.map(Self.quote).joined(separator: " ")
            let script = "tmux_binary=$(command -v tmux 2>/dev/null) || tmux_binary=; " +
                "if [ -z \"$tmux_binary\" ]; then for candidate in \(candidates); do " +
                "if [ -f \"$candidate\" ] && [ -x \"$candidate\" ]; then " +
                "tmux_binary=$candidate; break; fi; done; fi; " +
                "if [ -z \"$tmux_binary\" ]; then " +
                "printf '%s\\n' 'Farport: tmux is unavailable on this server.' >&2; exit 127; fi; "
            discovery = script
            // Advertise the native renderer's capabilities for this client, not all server clients.
            let launch = script + "exec \"$tmux_binary\" -T 256,RGB new-session -A -s \(name) " +
                "\\; set-option -t \(name) mouse on"
            // SSH runs exec requests through the account's login shell, which may not be POSIX.
            launchScript = launch
        }
    }
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
