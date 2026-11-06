# Reports command boundaries and the working directory to Rewarp. These use a
# private OSC with a token, rather than OSC 133 and OSC 7, because anything printed
# to the terminal could send those. The user's prompt is never touched.

builtin typeset -g _rewarp_running=0
builtin typeset -g _rewarp_installed=0
builtin source -- "${${(%):-%x}:A:h:h}/common.sh"

# Runs when the line editor starts reading, which is exactly when the shell can
# accept a command. A marker in PS1 would be simpler, but prompt themes rewrite
# PS1 on every prompt.
_rewarp_line_init() {
  [[ "$CONTEXT" == start ]] && _rewarp_report ready
  (( ${+widgets[_rewarp_user_line_init]} )) && zle _rewarp_user_line_init -- "$@"
  builtin return 0
}

# This wraps zle-line-init rather than using add-zle-hook-widget, because this has
# to run first. Some prompts, such as oh-my-posh, run the whole line edit inside
# their own zle-line-init, so anything chained after them would wait for Enter.
_rewarp_wrap_line_init() {
  builtin zmodload -F zsh/zleparameter 2>/dev/null
  [[ "${widgets[zle-line-init]}" == user:_rewarp_line_init ]] && builtin return
  if (( ${+widgets[zle-line-init]} )); then
    zle -A zle-line-init _rewarp_user_line_init
  fi
  zle -N zle-line-init _rewarp_line_init
}

# The app can't see the shell's real environment, which matters most when it was
# launched from Finder, so the parts completion needs are reported here.
_rewarp_precmd() {
  builtin local exit_code=$?

  if (( ! _rewarp_installed )); then
    _rewarp_installed=1
    # PROMPT_SP pads the screen to detect output with no trailing newline. Every
    # command has its own grid here, so all it would do is add a blank row.
    builtin unsetopt PROMPT_SP
  fi

  # Done here, not at load time, because the user's startup files have all run by
  # now. Repeated at every prompt in case something replaces it later.
  _rewarp_wrap_line_init
  _rewarp_prompt "$exit_code" "${(j: :)${(k)aliases}} ${(j: :)${(k)functions:#[_.+-]*}}"
}

_rewarp_preexec() {
  _rewarp_command_start "$1"
}

builtin autoload -Uz add-zsh-hook
add-zsh-hook precmd _rewarp_precmd
add-zsh-hook preexec _rewarp_preexec

# Keeps all this through `exec zsh`, which is what `omz reload` runs. A new shell only
# finds this directory through ZDOTDIR, and that can't stay exported, because
# installers would write the user's .zshrc here. zsh runs no hook before exec, so
# this sets it for the one process exec starts. It has to be an alias: a function
# called exec would undo `exec 3>&1` when it returned, and one called zsh would lose
# the -l of `exec -l zsh`. It's defined here, before the user's startup files,
# because an alias only reaches functions parsed after it, and `omz reload` is one.
# No token goes this way, because exec could be starting anything. The new shell
# asks the app for it.
if [[ -n "$_rewarp_socket" ]]; then
  builtin typeset -g _rewarp_zdotdir="${${(%):-%x}:A:h}"
  builtin alias exec='REWARP_USER_ZDOTDIR=${${(M)${(t)ZDOTDIR}:#*export*}:+$ZDOTDIR} ZDOTDIR=$_rewarp_zdotdir REWARP_SOCKET=$_rewarp_socket REWARP_SHELL_HELPER=$_rewarp_helper exec'
fi
