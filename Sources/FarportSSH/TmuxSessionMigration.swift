import FarportCore
import FarportLocalization
import Foundation

/// Rename the live server session, never recreate its shell or copy/replay its terminal contents.
enum TmuxSessionMigration {
    static let failureExitCode = 125
    static var failureMessage: String {
        L10n.text(
            "The saved tmux session could not be renamed safely. Existing sessions were kept. Try connecting again."
        )
    }

    static func script(for identity: TmuxSessionIdentity) -> String {
        let notice = L10n.text("Farport: another saved session was kept. To open it, run:")
        return """
        _farport_recovered=
        _farport_migration_failed() {
            printf '%s\\n' \(quote(failureMessage)) >&2
            exit \(failureExitCode)
        }
        _farport_find_session() {
            "$tmux_binary" display-message -p -t "=$1:" '#{session_id}' 2>/dev/null
        }
        _farport_previous=$(_farport_find_session \(identity.legacyName)) || _farport_previous=
        if [ -n "$_farport_previous" ]; then
            if "$tmux_binary" rename-session -t "$_farport_previous" \(identity.name) 2>/dev/null; then
                :
            else
                _farport_current=$(_farport_find_session \(identity.name)) || _farport_current=
                if [ "$_farport_current" = "$_farport_previous" ]; then
                    :
                elif [ -n "$_farport_current" ]; then
        \(preserveDuplicate(identity))
                else
                    _farport_migration_failed
                fi
            fi
        fi
        set --
        if [ -n "$_farport_recovered" ]; then
            set -- \\; display-message -d 15000 \(quote(notice + " tmux switch-client -t "))"$_farport_recovered"
        fi
        """ + "\n"
    }

    private static func preserveDuplicate(_ identity: TmuxSessionIdentity) -> String {
        """
                    case "$_farport_previous" in
                        '$'*) _farport_suffix=${_farport_previous#'$'} ;;
                        *) _farport_migration_failed ;;
                    esac
                    case "$_farport_suffix" in ''|*[!0-9]*) _farport_migration_failed ;; esac
                    _farport_recovered=\(identity.name)-recovered-$_farport_suffix
                    if "$tmux_binary" rename-session -t "$_farport_previous" "$_farport_recovered" 2>/dev/null; then
                        :
                    elif [ "$(_farport_find_session "$_farport_recovered")" != "$_farport_previous" ]; then
                        _farport_migration_failed
                    fi
        """
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
