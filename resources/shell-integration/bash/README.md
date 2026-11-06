# Bash integration

Supports macOS system Bash 3.2 and current Bash, with command blocks, exit status,
working-directory tracking, command/alias/function completions, and the Rewarp
input editor. CI exercises both system Bash and a current Homebrew installation.

The bootstrap obtains its private credential before running user startup files.
It then restores Bash mode and ENV, reads `/etc/profile` and the first readable
`.bash_profile`, `.bash_login`, or `.profile`, and installs prompt hooks after the
user's configuration. A profile that normally sources `.bashrc` still does so.

The adapter preserves scalar and array PROMPT_COMMAND values, user PS1 content,
existing DEBUG traps, and HISTCONTROL. Modern Bash uses PS0 for preexec; Bash 3.2
uses a guarded DEBUG hook. Encoding, framing, lifecycle, and metadata handling
are shared with the other adapters. Command labels come from the submitted text,
so commands omitted from shell history still form correct blocks.

The authenticated helper bootstrap is single-use. Normal child commands cannot
retrieve its token afterward. Set `REWARP_SHELL_INTEGRATION=none` for a standard
terminal without integration.
