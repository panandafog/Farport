import FarportCore
import Foundation

struct TerminalLaunchPlan {
    var command: String? { launchScript(shell: nil).map(Self.shellCommand) }
    private let discovery: String
    private let sessionName: String?
    var requiresTmux: Bool { sessionName != nil }

    func command(colors: TerminalDecorationColors?) throws -> String? {
        let shell: String?
        if let colors, colors.useAppAccent, let accent = colors.accent {
            shell = try ShellPromptBootstrap.script(accent: accent)
        } else { shell = nil }
        guard var script = launchScript(shell: shell) else { return nil }
        if let colors, requiresTmux { script += " \\; " + styleCommands(colors) }
        return Self.shellCommand(script)
    }

    private func launchScript(shell: String?) -> String? {
        guard let sessionName else { return shell }
        var launch = discovery + "exec \"$tmux_binary\" -T 256,RGB new-session -A -s \(sessionName)"
        if let shell { launch += " " + Self.quote(Self.shellCommand(shell)) }
        return launch + " \\; set-option -t \(sessionName) mouse on"
    }

    private static func shellCommand(_ script: String) -> String {
        "exec /bin/sh -c " + Self.quote(script)
    }

    func decorationCommand(_ colors: TerminalDecorationColors) -> String? {
        guard sessionName != nil else { return nil }
        return "exec /bin/sh -c " + Self.quote(discovery + "exec \"$tmux_binary\" " + styleCommands(colors))
    }

    private func styleCommands(_ colors: TerminalDecorationColors) -> String {
        guard let sessionName else { return "" }
        guard colors.useAppAccent else {
            return "set-option -u -t \(sessionName) status-style \\; " +
                "set-window-option -u -t \(sessionName) mode-style"
        }
        let style = String(format: "fg=#%06x,bg=#%06x", colors.foreground, colors.background)
        return "set-option -t \(sessionName) status-style \(Self.quote(style)) \\; " +
            "set-window-option -t \(sessionName) mode-style \(Self.quote(style))"
    }

    init(profile: HostProfile, sessionID: UUID? = nil,
         tmuxSearchPaths: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]) {
        switch profile.terminalResumeStrategy {
        case .none:
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
        }
    }
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
