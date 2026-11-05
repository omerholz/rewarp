# Reports command boundaries to Rewarp with OSC 133, and the working directory
# with OSC 7. The end of a command uses the private channel with a token, because
# a command can print OSC 133 too. The user's prompt is never touched.

builtin typeset -g _rewarp_running=0
builtin typeset -g _rewarp_installed=0

_rewarp_urlencode() {
  builtin setopt local_options extended_glob
  builtin local LC_ALL=C
  REPLY=${1//(#m)[^A-Za-z0-9._~\/-]/%${(l:2::0:)$(( [##16] #MATCH ))}}
}

# Runs when the line editor starts reading, which is exactly when the shell can
# accept a command. A marker in PS1 would be simpler, but prompt themes rewrite
# PS1 on every prompt.
_rewarp_line_init() {
  [[ "$CONTEXT" == start ]] && builtin printf '\e]133;B\a'
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
_rewarp_report_environment() {
  [[ "$PATH" == "$_rewarp_reported_path" ]] && builtin return
  _rewarp_reported_path="$PATH"
  _rewarp_urlencode "$PATH"
  builtin printf '\e]7701;path=%s\a' "$REPLY"
  _rewarp_urlencode "${(j: :)${(k)aliases}} ${(j: :)${(k)functions:#[_.+-]*}}"
  builtin printf '\e]7701;names=%s\a' "$REPLY"
}

_rewarp_precmd() {
  builtin local exit_code=$?

  if (( _rewarp_running )); then
    builtin printf '\e]7701;done=%s;%d\a' "$_rewarp_token" "$exit_code"
    _rewarp_running=0
  fi

  if (( ! _rewarp_installed )); then
    _rewarp_installed=1
    # PROMPT_SP pads the screen to detect output with no trailing newline. Every
    # command has its own grid here, so all it would do is add a blank row.
    builtin unsetopt PROMPT_SP
  fi

  # Done here, not at load time, because the user's startup files have all run by
  # now. Repeated at every prompt in case something replaces it later.
  _rewarp_wrap_line_init
  _rewarp_report_environment

  _rewarp_urlencode "$PWD"
  builtin printf '\e]7;file://%s%s\a\e]133;A\a' "${HOST}" "$REPLY"
}

_rewarp_preexec() {
  _rewarp_urlencode "$1"
  builtin printf '\e]133;C;cmdline_url=%s\a' "$REPLY"
  _rewarp_running=1
}

builtin autoload -Uz add-zsh-hook
add-zsh-hook precmd _rewarp_precmd
add-zsh-hook preexec _rewarp_preexec
