# Rewarp starts zsh with ZDOTDIR pointing here so this file runs first. It puts
# ZDOTDIR back, runs the user's own .zshenv, and loads the integration. The rest
# of the user's startup files then run as usual.

# The token proves that a report came from this shell. It stays a shell variable, so
# the commands the shell runs never inherit it, and it never passes through the
# environment, so they can't read it from there either. The app gives it to the
# pane's own process and nothing else. exec keeps the pid, so a shell started by
# `exec zsh` gets it the same way, and nothing else can get an answer.
builtin typeset -g _rewarp_token= _rewarp_socket="$REWARP_SOCKET"
builtin unset REWARP_SOCKET
builtin typeset -g +x _rewarp_helper="$REWARP_SHELL_HELPER"
builtin unset REWARP_SHELL_HELPER

if [[ -n "$_rewarp_socket" && -o interactive ]] && builtin zmodload zsh/net/socket 2>/dev/null; then
  if zsocket "$_rewarp_socket" 2>/dev/null; then
    builtin read -r -t 2 -u "$REPLY" _rewarp_token
    exec {REPLY}<&-
  fi
  builtin zmodload -u zsh/net/socket
fi

# Says the integration is on its way, so that a slow .zshrc isn't mistaken for a
# shell without integration.
[[ -o interactive && -n "$_rewarp_token" ]] && builtin printf '\e]7701;hello=%s;\a' "$_rewarp_token"

# Empty when exec's alias found no exported ZDOTDIR to pass on.
if [[ -n "$REWARP_USER_ZDOTDIR" ]]; then
  builtin export ZDOTDIR="$REWARP_USER_ZDOTDIR"
else
  builtin unset ZDOTDIR
fi
builtin unset REWARP_USER_ZDOTDIR

{
  builtin typeset _rewarp_user_env="${ZDOTDIR-$HOME}/.zshenv"
  [[ -r "$_rewarp_user_env" ]] && builtin source -- "$_rewarp_user_env"
} always {
  builtin unset _rewarp_user_env
  if [[ -o interactive && -n "$_rewarp_token" ]]; then
    builtin source -- "${${(%):-%x}:A:h}/rewarp-integration.zsh"
  fi
}
