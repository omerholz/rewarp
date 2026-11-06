# Fish adapter

Fish uses its native `fish_preexec`, `fish_postexec`, and `fish_prompt` events.
The native shared bridge handles credential transport, byte encoding, and OSC
framing. Fish keeps only its event hooks, metadata collection, and startup logic.

The launch retains login-shell semantics and Fish's native initialization,
including universal-variable loading and synchronization. A private temporary XDG
wrapper claims a one-use credential at the user `conf.d` stage, before user
snippets or vendor programs run. It restores the user's XDG paths, loads snippets
by their real paths, and masks matching basenames so Fish retains user > system >
vendor precedence. The system and user `config.fish` still run in their normal
order. The wrapper links the real `fish_variables` file; Fish resolves that link
before atomic updates, so ordinary Fish sessions continue sharing those settings.
It is removed after the pane shell exits.
The credential stays unexported and report calls suppress Fish tracing locally.

The adapter preserves user prompt functions and the right prompt. A small wrapper
reports readiness after the left prompt runs, calling the original function first
so it sees the preceding command's `$status` and `$pipestatus`. Prompt functions
replaced after startup are wrapped on the next prompt cycle.

Rewarp receives command boundaries, exit status, working directory, PATH, and
function/abbreviation names for its command editor, blocks, and suggestions.
Fish retains execution, history, expansion, and its native interactive behavior.
Shared completion quoting escapes percent signs so a filename such as `%self`
cannot turn into Fish's process ID. Native literal-word and app completion tests
cover this alongside shell metacharacters.
Set `REWARP_SHELL_INTEGRATION=none` when launching Rewarp to use a plain terminal.

Run `python3 Tests/ShellIntegration/test_fish_adapter.py` for real-PTY adapter
coverage, and `python3 tests-e2e/run.py shell_fish_` on macOS for app coverage.
`REWARP_TEST_FISH` can select a specific Fish executable.
