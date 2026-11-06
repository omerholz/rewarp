# Shared by the zsh and bash adapters. Fish uses the same native protocol bridge.
# Credentials stay unexported; the bridge receives them through an anonymous pipe.
_rewarp_report() {
  builtin local _rewarp_trace= _rewarp_result
  case $- in *x*) _rewarp_trace=1; builtin set +x ;; esac
  { builtin printf '%s\n' "$_rewarp_token"; builtin printf '%s' "${2-}"; } |
    "$_rewarp_helper" report "$1"
  _rewarp_result=$?
  [ "$_rewarp_trace" != 1 ] || builtin set -x
  return "$_rewarp_result"
}

_rewarp_report_environment() {
  if [ "${_rewarp_reported_path-}" != "$PATH" ]; then
    _rewarp_reported_path=$PATH
    _rewarp_report path "$PATH"
  fi
  if [ "${_rewarp_reported_names-}" != "$1" ]; then
    _rewarp_reported_names=$1
    _rewarp_report names "$1"
  fi
}

_rewarp_command_start() {
  _rewarp_report start "$1"
  _rewarp_running=1
}

_rewarp_prompt() {
  if [ "${_rewarp_running-0}" = 1 ]; then
    _rewarp_report done "$1"
    _rewarp_running=0
  fi
  # End the command before sending large metadata: the shell terminal accepts
  # larger reports than a command block's output terminal.
  _rewarp_report_environment "${2-}"
  _rewarp_report cwd "$PWD"
  _rewarp_report prompt
}
