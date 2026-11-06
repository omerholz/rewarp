# Shell integration architecture

Rewarp launches the account's configured login shell. The test harness explicitly
selects a shell so tests do not depend on the CI host's account settings.

The app's stream router consumes the same authenticated `7701` protocol for every
shell. `RewarpShellBridge` owns byte encoding and OSC framing; adapters pass the
unexported credential and raw values through stdin, never through argv or the
environment. Control characters, UTF-8 bytes, filenames, and multiline commands
are encoded consistently in one implementation.

`resources/shell-integration/common.sh` owns the POSIX-family command lifecycle
and change detection for PATH, aliases, and functions. It ends the command before
sending large metadata reports so those reports reach the shell terminal's larger
parser limit. Shell adapters own only startup-file semantics, prompt/readiness
hooks, and shell-specific ways to enumerate commands.

The zsh adapter preserves normal `.zshenv`, `.zprofile`, `.zshrc`, and `.zlogin`
loading, custom ZDOTDIR, prompt widgets, and `exec zsh`/Oh My Zsh reload behavior.
Zsh's token handoff remains restricted to the pane shell's process ID. The shared
transport also supports a separately enabled, one-use helper bootstrap for shells
without native sockets. The app verifies both the helper's executable path and
its parent PID using kernel metadata; subsequent helper requests are denied. This
path is disabled for zsh. Future adapters must claim the credential before loading
user startup files, so programs those files run cannot consume the bootstrap.
The bridge is located beside the app binary, rather than on PATH or in a working
directory, and is bundled as a helper executable.

Build with `make build`, then run:

```sh
python3 Tests/ShellIntegration/test_bridge.py
scripts/fetch-shell-fixtures.sh
python3 tests-e2e/run.py shell_
```

The prompt-framework fixture is an actual, commit-pinned Oh My Zsh checkout. Tests
use temporary homes and verify startup files, custom configuration directories,
post-startup aliases, git-plugin loading, exit status, reload, and credential
privacy. The shell-integration workflow runs both native protocol tests and real
macOS app tests. Bash and fish adapters are separate follow-up PRs to this shared
foundation; unsupported shells continue to use the ordinary terminal fallback.
