_FARPORT_GLOBAL_RCS=0
[[ -o GLOBAL_RCS ]] && _FARPORT_GLOBAL_RCS=1
unsetopt GLOBAL_RCS
_farport_source_global_file() {
    local _farport_name=${1#.} _farport_candidate
    for _farport_candidate in "${SHELL:h:h}/etc/zsh/$_farport_name" "${SHELL:h:h}/etc/$_farport_name" \
        "/etc/zsh/$_farport_name" "/etc/$_farport_name"; do
        if [[ -r $_farport_candidate ]]; then builtin source "$_farport_candidate"; break; fi
    done
}
_farport_source_user_file() {
    local _farport_file=$1
    if [[ $_FARPORT_ZDOTDIR_SET == 1 ]]; then
        export ZDOTDIR="$_FARPORT_USER_ZDOTDIR"
    else
        unset ZDOTDIR
    fi
    if [[ $_FARPORT_GLOBAL_RCS == 1 ]]; then setopt GLOBAL_RCS; else unsetopt GLOBAL_RCS; fi
    # System files must also see the user's directory (notably macOS's default HISTFILE).
    if [[ $_farport_file != .zshenv && -o GLOBAL_RCS ]]; then
        _farport_source_global_file "$_farport_file"
    fi
    if [[ -o RCS && -r "${ZDOTDIR-$HOME}/$_farport_file" ]]; then
        builtin source "${ZDOTDIR-$HOME}/$_farport_file"
    fi
    _FARPORT_ZDOTDIR_SET=${+ZDOTDIR}
    _FARPORT_USER_ZDOTDIR=${ZDOTDIR-$HOME}
    _FARPORT_GLOBAL_RCS=0
    [[ -o GLOBAL_RCS ]] && _FARPORT_GLOBAL_RCS=1
    if [[ -o RCS ]]; then
        unsetopt GLOBAL_RCS
        export ZDOTDIR="$_FARPORT_BOOTSTRAP_DIR"
    fi
}
_farport_source_user_file .zshenv
