# A trusted first input line sources this into an ordinary interactive login
# Bash with --noprofile. This also works around Apple Bash 3.2 ignoring POSIX ENV.
[[ $- == *i* ]] || return 0
_rewarp_bootstrap_trace=0
case $- in *x*) _rewarp_bootstrap_trace=1; builtin set +x ;; esac
_rewarp_authenticated=0
_rewarp_init=$REWARP_SHELL_INIT
_rewarp_helper=$REWARP_SHELL_HELPER
_rewarp_socket=$REWARP_SOCKET
builtin export -n _rewarp_init _rewarp_helper _rewarp_socket _rewarp_token
_rewarp_token=$(builtin exec "$_rewarp_helper" token "$_rewarp_socket" 2>/dev/null) || _rewarp_token=
[[ -n $_rewarp_token ]] && _rewarp_authenticated=1
if [[ ${REWARP_USER_HISTCONTROL_SET-} == 1 ]]; then
  HISTCONTROL=$REWARP_USER_HISTCONTROL
  builtin export HISTCONTROL
else
  builtin unset HISTCONTROL
fi
if [[ ${REWARP_USER_HISTFILE_SET-} == 1 ]]; then
  HISTFILE=$REWARP_USER_HISTFILE
  builtin export HISTFILE
else
  HISTFILE=$HOME/.bash_history
  builtin export -n HISTFILE
fi
builtin unset REWARP_SOCKET REWARP_SHELL_HELPER REWARP_SHELL_INIT
builtin unset REWARP_USER_HISTCONTROL REWARP_USER_HISTCONTROL_SET REWARP_USER_HISTFILE REWARP_USER_HISTFILE_SET
builtin source -- "${_rewarp_init%/bash/*}/common.sh"
(( _rewarp_authenticated )) && _rewarp_report hello
(( _rewarp_bootstrap_trace )) && builtin set -x

# --noprofile prevented these from running before the private bootstrap. Read
# precisely the files an interactive Bash login shell normally chooses.
if [[ $OSTYPE == darwin* && -f /private/var/db/ManagedConfigurationFiles/com.apple.bash/etc/profile ]]; then
  builtin source /private/var/db/ManagedConfigurationFiles/com.apple.bash/etc/profile
elif [[ -r /etc/profile ]]; then
  builtin source /etc/profile
fi
for _rewarp_profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
  if [[ -r $_rewarp_profile ]]; then
    builtin source -- "$_rewarp_profile"
    break
  fi
done
builtin unset _rewarp_profile
[[ -n ${HISTFILE-} && -r $HISTFILE ]] && builtin history -r "$HISTFILE"
(( _rewarp_authenticated )) || return 0

_rewarp_capture_status() {
  _rewarp_status=$?
  _rewarp_at_prompt=0
  return "$_rewarp_status"
}

_rewarp_precmd() {
  builtin local names name
  names=$(builtin compgen -A alias)
  names=${names//$'\n'/ }
  while IFS= builtin read -r name; do
    case "$name" in _*) ;; *) names="$names $name" ;; esac
  done < <(builtin compgen -A function)
  _rewarp_prompt "${_rewarp_status-0}" "$names"
  [[ $PS1 == *'\[$(_rewarp_report ready)\]'* ]] || PS1=$PS1'\[$(_rewarp_report ready)\]'
  if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
    [[ ${PS0-} == *'$(_rewarp_report start)'* ]] || PS0='$(_rewarp_report start)'${PS0-}
  fi
  _rewarp_running=1
  _rewarp_at_prompt=1
  return 0
}

# Capture status while expanding a no-op stdout duplication on a command group.
# A prefix function or assignment command would overwrite PIPESTATUS before the
# user's prompt hook can read it. The group retains the user's normal stdin.
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )) &&
    [[ $(builtin declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
  PROMPT_COMMAND=("${PROMPT_COMMAND[@]}")
  PROMPT_COMMAND[0]=$'{\n'${PROMPT_COMMAND[0]:-:}$'\n} 1>&$((_rewarp_status=$?, _rewarp_at_prompt=0, 1))'
  PROMPT_COMMAND+=('_rewarp_precmd')
elif (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  PROMPT_COMMAND=$'{\n'${PROMPT_COMMAND:-:}$'\n} 1>&$((_rewarp_status=$?, _rewarp_at_prompt=0, 1))\n_rewarp_precmd'
else
  # Bash 3.2 itself clears PIPESTATUS when any DEBUG trap runs. Keep the legacy
  # status hook simple; prompts needing pipeline details should use current Bash.
  PROMPT_COMMAND='_rewarp_capture_status "$_"'$'\n'${PROMPT_COMMAND-}$'\n''_rewarp_precmd'
fi

# Bash 4.4+ has PS0, which runs once per accepted command. The system Bash 3.2
# on macOS needs a DEBUG hook instead. Preserve a user's existing trap body.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  _rewarp_debug() {
    [[ ${_rewarp_at_prompt-0} == 1 && ${BASH_SUBSHELL-0} == 0 ]] || return 0
    case $BASH_COMMAND in _rewarp_*) return 0 ;; esac
    _rewarp_at_prompt=0
    _rewarp_command_start ''
  }
  _rewarp_return_status() { return "$1"; }
  _rewarp_prior_debug=$(builtin trap -p DEBUG)
  builtin eval "_rewarp_trap_argv=(${_rewarp_prior_debug:-})"
  _rewarp_prior_debug=${_rewarp_trap_argv[2]-:}
  builtin trap '_rewarp_debug_status=$? _rewarp_debug_arg=$_; _rewarp_return_status "$_rewarp_debug_status" "$_rewarp_debug_arg"; '"$_rewarp_prior_debug"$'\n''_rewarp_debug_result=$?; _rewarp_debug; _rewarp_return_status "$_rewarp_debug_result" "$_rewarp_debug_arg"' DEBUG
fi
