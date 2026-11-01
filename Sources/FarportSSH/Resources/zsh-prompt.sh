_farport_source_user_file .zlogin
if [[ $_FARPORT_ZDOTDIR_SET == 1 ]]; then
    export ZDOTDIR="$_FARPORT_USER_ZDOTDIR"
else
    unset ZDOTDIR
fi
if [[ $_FARPORT_GLOBAL_RCS == 1 ]]; then setopt GLOBAL_RCS; else unsetopt GLOBAL_RCS; fi
unset _FARPORT_ZDOTDIR_SET _FARPORT_USER_ZDOTDIR _FARPORT_BOOTSTRAP_DIR _FARPORT_GLOBAL_RCS
unfunction _farport_source_user_file _farport_source_global_file

_farport_set_prompt() {
    local _farport_status=$?
    PROMPT=$'%{\e[38;2;@FARPORT_RGB@m%}%n@%m:%~%{\e[0m%}%# '
    RPROMPT=''
    return "$_farport_status"
}
typeset -ga precmd_functions
precmd_functions+=(_farport_set_prompt)
_farport_set_prompt
