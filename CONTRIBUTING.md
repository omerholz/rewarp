# Contributing

Rewarp is an early macOS terminal project. Small fixes, reproducible bug reports,
and focused tests are welcome. [The design](docs/design.md) and
[parity checklist](docs/warp-parity.md) describe the current direction.

Rewarp is maintained by @omerholz. Contributions are welcome through fork-based
pull requests. The maintainer decides which changes are accepted and merged.
Please discuss substantial changes in an issue before implementation. Contributors
do not need write access to this repository to submit a pull request.

## Development

Use macOS 14 or later, Swift 6 or later (Swift Testing is used by the tests),
Zig 0.17.0, Python 3, and the Xcode Command Line Tools. CI pins Zig 0.17.0.
Full Xcode can also supply the toolchain. Follow the [build instructions](README.md#build).
Changes are ordinary SwiftPM sources; no Xcode project is required.

```sh
make build
make test
make e2e
make app
make secrets  # requires gitleaks
python3 -m unittest discover -s tests-tools -v  # governance tooling
```

`make test FILTER=RouterTests` and `make e2e FILTER=blocks` narrow a run.
UI tests require a logged-in graphical macOS session and Metal; they may fail
on headless runners. Run the full suite locally before a release. Debug app
automation is described in [SECURITY.md](SECURITY.md).

Keep generated output (`.build`, `vendor`, `dist`, generated Ghostty headers)
out of commits. For changes to terminal routing, shell startup, quoting, or
PTY lifetime, include a regression test that exercises the relevant boundary.
Use synthetic data; reports and screenshots should not contain your real
history, hostnames, credentials, or private paths.

## Pull requests

Explain the observed problem, the resulting behavior, and the checks you ran.
State when a macOS check could not be run. Keep performance claims reproducible:
record hardware, macOS/tool versions, build modes, workload, and results from
`make bench` when a change affects rendering or output throughput.

Follow nearby code style. Keep the core independent of AppKit. Access terminal
state through `PaneSession.withState` while holding the session lock; callbacks
must not recursively take it. Escape all completion insertions and treat PTY
output as attacker-controlled.

The parity runner updates checked boxes after a full end-to-end run. Those boxes
are historical test evidence, not a guarantee of complete feature support.
Review any resulting documentation diff.

## Licensing and provenance

Contributions are licensed under the repository's [MIT license](LICENSE).
Submit only code and assets you have the right to contribute. Rewarp's stated
approach is to implement behavior independently from public documentation;
do not copy Warp source or proprietary assets. Preserve third-party attribution
and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `LICENSES/` when
dependencies change. This is a volunteer project; response times vary.
