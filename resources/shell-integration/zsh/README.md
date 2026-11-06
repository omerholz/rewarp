# zsh integration

Supports normal interactive login startup, custom ZDOTDIR, prompt themes and
widgets, and `exec zsh`/Oh My Zsh reload. The compatibility suite uses an actual,
commit-pinned Oh My Zsh checkout with its git plugin and robbyrussell theme.

The adapter preserves the user's startup files and prompt. Common report framing,
byte encoding, command lifecycle, and metadata change detection live outside this
shell-specific adapter. Integration credentials are unexported and suppressed
from shell tracing. Set `REWARP_SHELL_INTEGRATION=none` to use an ordinary terminal.
