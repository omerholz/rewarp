# Security

Rewarp is experimental terminal software. Only the latest source revision is
maintained; there is no security response SLA or supported stable release yet.

## Reporting a vulnerability

Use the repository's **Security → Report a vulnerability** feature if it is
enabled. The maintainer should enable private vulnerability reporting when
publishing the repository. Do not include exploit details, credentials,
terminal recordings, or private output in public issues. If private reporting
is unavailable, open an issue asking the maintainer to enable it, without
including the vulnerability details.

Include the revision, macOS version, build mode, affected shell, expected and
actual behavior, and a minimal reproduction using synthetic data.

## Trust boundaries

- Terminal output is untrusted. Command boundaries and working-directory
  reports from integrated zsh require a per-pane random token. The shell receives
  it through a local socket that checks the connecting PID; it is not an
  environment variable or a cryptographic signature. OSC 133 is ignored.
- That token protects against programs merely printing escape sequences. It is
  not isolation from malicious shell startup files, shell functions, commands
  that inspect shell variables, or other code running as the same user.
- Without integration, OSC 7 directory reports are accepted from the plain
  shell terminal. They can be spoofed by printed output.
- OSC 52 does not access the clipboard. The app does not currently open links
  from terminal output. User-initiated copy/paste accesses the macOS pasteboard.
- Completion reads local files, Git refs, PATH, SSH configuration/known hosts,
  and package scripts/Makefile targets. Candidate text is shell-escaped and
  control characters are excluded. Completion does not execute those files.
- Shells and commands run with the logged-in user's privileges. The app is not
  sandboxed. Trusted shell startup files run normally, including any network
  activity or history writes they configure.
- `REWARP_SEND`, `REWARP_CONTROL`, `REWARP_CAPTURE`, `REWARP_STATS`,
  `REWARP_WAIT`, `REWARP_VISIBLE`, and `REWARP_SHELL` are local automation
  interfaces. They can run commands, synthesize input, capture output, or write
  files when explicitly set in the app's launch environment. Do not launch the
  app with environment settings from an untrusted source. `REWARP_*` values are
  removed before launching pane shells; the app adds its own integration values.

## Local data and resource limits

Rewarp reads shell history for suggestions and keeps commands and output in
memory. It has no telemetry, account service, or application network client in
the reviewed source. It does not persist terminal sessions. The shell may write
its own history; macOS may retain crash reports or swap. Tab position is stored
in `UserDefaults`. Automation captures and diagnostic output can contain secrets.

A block retains up to 50,000 scrollback rows, but the number of blocks has no
session-wide memory cap. Heavy output can exhaust memory. Find and regex filters
run on the main thread and may stall the UI on large or adversarial inputs.
See [known limits](docs/design.md#known-limits). Release builds retain Swift
safety checks and use Zig `ReleaseSafe` for libghostty-vt.

## Secret scanning

With [Gitleaks](https://github.com/gitleaks/gitleaks) installed, run:

```sh
make secrets
```

This scans reachable Git history and the tracked source plus untracked,
non-ignored files. Reports are redacted. It is a useful check, not proof that
credentials or private information are absent. Build output and ignored local
files are not part of the source publication. Never attach raw shell history,
private keys, signing credentials, or `.env` files to an issue or release.
