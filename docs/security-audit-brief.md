# Rewarp independent audit brief

Prepared for an OSTIF funding inquiry or auditor intake. Not submitted.

Rewarp is an early-stage native macOS terminal emulator. It combines a Swift UI
and renderer, a C PTY launcher, and a pinned libghostty-vt Zig parser. We seek an
audit by reviewers with macOS terminal-emulator, Swift/native-code, PTY/process,
and terminal-protocol experience. Radically Open Security is one candidate for
the owner to evaluate. No auditor availability, funding, or engagement is assumed.

## Threat model and scope

An attacker can provide terminal output from SSH or a local command, file contents,
repository files and directory names, completion candidates, escape sequences,
and large or fragmented streams. Review whether those inputs can cause unintended
command execution, clipboard disclosure/modification, memory corruption, process
descriptor leakage, authority spoofing, or denial of service.

Priority boundaries:

- PTY bytes through Swift routing, C ABI callbacks, and the Zig parser.
- Authenticated shell-integration messages, token handoff, and report framing.
- Paste/command encoding, hostile filenames, completions, and shell quoting.
- Child launch, inherited descriptors, working directories, and shell startup.
- Clipboard protocols, links, titles, query replies, output limits, and resizing.
- Command-history privacy and release exclusion of automation interfaces.
- Ghostty update/advisory handling and supply-chain/release configuration.

## Evidence available

The repository contains source, unit and real-shell tests, app-driven UI tests,
deterministic terminal mutation tests, macOS CI configuration, CodeQL Swift/C
configuration, a prepared Sonar Swift scan, and Ghostty advisory review evidence.
See [security.md](security.md) for exact checks and limitations.

## Requested deliverables

A scoped audit plan and estimate; reproducible findings with severity and attack
preconditions; minimized regression inputs; remediation guidance; retesting of
fixes; and a coordinated publication plan agreed with the maintainer.

## Owner information required before submission

Rewarp uses the MIT License. Confirm the intended public-release plan; provide
the maintainer's contact details; select a reviewed commit or release candidate; supply actual
macOS CI/fuzz results and performance measurements; and agree the audit scope,
funding request, and disclosure arrangements.
