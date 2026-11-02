import FarportCore
import FarportLocalization
import Foundation

/// Starts one new shell with private temporary startup shims. Never edits user configuration.
enum ShellPromptBootstrap {
    static func script(accent: UInt32) throws -> String {
        let warning = quote(L10n.text("Farport: prompt styling is unavailable; using the server's shell."))
        let startup = try startupFiles(accent: accent)
        return """
        \(preamble(warning: warning))
        case ${_farport_shell##*/} in
            bash)
        \(write(startup.bash, to: "bashrc"))
                umask "$_farport_umask"
                "$_farport_shell" --rcfile "$_farport_dir/bashrc" -i
                ;;
            zsh)
        \(write(try resource("zsh-startup"), to: ".zshenv"))
        \(write("_farport_source_user_file .zprofile\n", to: ".zprofile"))
        \(write("_farport_source_user_file .zshrc\n", to: ".zshrc"))
        \(write(startup.zsh, to: ".zlogin"))
                export _FARPORT_BOOTSTRAP_DIR="$_farport_dir"
                if [ "${ZDOTDIR+x}" = x ]; then
                    export _FARPORT_ZDOTDIR_SET=1 _FARPORT_USER_ZDOTDIR="$ZDOTDIR"
                else
                    export _FARPORT_ZDOTDIR_SET=0 _FARPORT_USER_ZDOTDIR="$HOME"
                fi
                export ZDOTDIR="$_farport_dir"
                umask "$_farport_umask"
                "$_farport_shell" -il
                ;;
        esac
        exit $?
        """
    }

    private static func preamble(warning: String) -> String {
        """
        _farport_shell=${SHELL:-/bin/sh}
        case ${_farport_shell##*/} in
            bash|zsh) ;;
            *) printf '%s\\n' \(warning); exec "$_farport_shell" -l ;;
        esac
        _farport_umask=$(umask)
        umask 077
        _farport_dir=$(mktemp -d "${TMPDIR:-/tmp}/farport-shell.XXXXXXXX") || {
            umask "$_farport_umask"
            printf '%s\\n' \(warning)
            exec "$_farport_shell" -l
        }
        readonly _farport_dir
        _farport_cleanup() {
            rm -f "$_farport_dir/bashrc" "$_farport_dir/.zshenv" "$_farport_dir/.zprofile" \
                "$_farport_dir/.zshrc" "$_farport_dir/.zlogin"
            rmdir "$_farport_dir" 2>/dev/null || :
        }
        trap '_farport_cleanup' 0
        trap 'exit 129' HUP
        trap 'exit 143' TERM
        _farport_fallback() {
            _farport_cleanup
            trap - 0 HUP TERM
            umask "$_farport_umask"
            printf '%s\\n' \(warning)
            exec "$_farport_shell" -l
        }
        """
    }

    private static func startupFiles(accent: UInt32) throws -> (bash: String, zsh: String) {
        let rgb = "\((accent >> 16) & 255);\((accent >> 8) & 255);\(accent & 255)"
        let bash = try resource("bash-prompt").replacingOccurrences(of: "@FARPORT_RGB@", with: rgb)
        let zsh = try resource("zsh-prompt").replacingOccurrences(of: "@FARPORT_RGB@", with: rgb)
        return (bash, zsh)
    }

    private static func write(_ content: String, to name: String) -> String {
        "cat >\"$_farport_dir/\(name)\" <<'FARPORT_PROMPT_STARTUP'\n" + content +
            "\nFARPORT_PROMPT_STARTUP\nif [ $? -ne 0 ]; then _farport_fallback; fi\n"
    }

    private static func resource(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "sh"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw TerminalConnectionError.configuration(L10n.text("Shell prompt integration resources are missing."))
        }
        return content
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
