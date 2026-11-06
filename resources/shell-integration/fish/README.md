# Fish adapter

Fish uses its native `fish_preexec`, `fish_postexec`, and `fish_prompt` events.
The native shared bridge handles credential transport, byte encoding, and OSC
framing. Fish keeps only its event hooks, metadata collection, and startup logic.

The launch retains login-shell semantics and claims a one-use credential before
reading ordinary startup files. It then loads Fish's internal configuration,
system configuration, and the user's XDG `config.fish` in their usual order. Fish's
own internal initialization handles user, system, and vendor `conf.d` precedence.
The credential stays unexported and report calls suppress Fish tracing locally.

The adapter preserves user prompt functions and the right prompt. A small wrapper
reports readiness after the left prompt runs, calling the original function first
so it sees the preceding command's `$status` and `$pipestatus`. Prompt functions
replaced after startup are wrapped on the next prompt cycle.

Rewarp receives command boundaries, exit status, working directory, PATH, and
function/abbreviation names for its command editor, blocks, and suggestions.
Fish retains execution, history, expansion, and its native interactive behavior.
Set `REWARP_SHELL_INTEGRATION=none` when launching Rewarp to use a plain terminal.

Run `python3 Tests/ShellIntegration/test_fish_adapter.py` for real-PTY adapter
coverage, and `python3 tests-e2e/run.py shell_fish_` on macOS for app coverage.
`REWARP_TEST_FISH` can select a specific Fish executable.
