# Loaded only for the explicitly requested session. User files are read, never changed.
if [ -r /etc/profile ]; then . /etc/profile; fi
for _farport_profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [ -r "$_farport_profile" ]; then . "$_farport_profile"; break; fi
done
unset _farport_profile

_farport_set_prompt() {
    local _farport_status=$?
    PS1='\[\e[38;2;@FARPORT_RGB@m\]\u@\h:\w\[\e[0m\]\$ '
    return "$_farport_status"
}
case "$(declare -p PROMPT_COMMAND 2>/dev/null)" in
    'declare -a'*)
        if (( BASH_VERSINFO[0] > 5 || BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1 )); then
            PROMPT_COMMAND+=(_farport_set_prompt)
        else
            PROMPT_COMMAND[0]="${PROMPT_COMMAND[0]-}"$'\n''_farport_set_prompt'
        fi
        ;;
    *) PROMPT_COMMAND="${PROMPT_COMMAND-}"$'\n''_farport_set_prompt' ;;
esac
_farport_set_prompt
