# Rewarp starts zsh with ZDOTDIR pointing here so this file runs first. It puts
# ZDOTDIR back, runs the user's own .zshenv, and loads the integration. The rest
# of the user's startup files then run as usual.

# Says the integration is on its way, so that a slow .zshrc isn't mistaken for a
# shell without integration.
[[ -o interactive ]] && builtin printf '\e]7701;hello=1\a'

# Proves that the end of a command was reported by this shell. It stays a shell
# variable, so the commands the shell runs never inherit it.
builtin typeset -g _rewarp_token="$REWARP_TOKEN"
builtin unset REWARP_TOKEN

if [[ -n "${REWARP_USER_ZDOTDIR+set}" ]]; then
  builtin export ZDOTDIR="$REWARP_USER_ZDOTDIR"
  builtin unset REWARP_USER_ZDOTDIR
else
  builtin unset ZDOTDIR
fi

{
  builtin typeset _rewarp_user_env="${ZDOTDIR-$HOME}/.zshenv"
  [[ -r "$_rewarp_user_env" ]] && builtin source -- "$_rewarp_user_env"
} always {
  builtin unset _rewarp_user_env
  if [[ -o interactive ]]; then
    builtin source -- "${${(%):-%x}:A:h}/rewarp-integration.zsh"
  fi
}
