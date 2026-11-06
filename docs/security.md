# Security checks and service setup

Rewarp treats terminal output, repository contents, filenames, and remote hosts
as untrusted input. Swift and the C shim are checked separately from the embedded
Ghostty Zig parser. A clean static scan does not establish that output is safe.

## Local checks

On macOS with the pinned Zig version and Xcode Command Line Tools:

```sh
make test
scripts/test.sh -c release
make e2e FILTER=security_
make fuzz
make app
python3 scripts/check-release.py dist/Rewarp.app/Contents/MacOS/Rewarp
```

`make fuzz` runs 10,000 deterministic mutations through the Ghostty C API and
`PaneSession.ingest`, using the same seed and varied PTY read boundaries. Set
`REWARP_FUZZ_CASES` to 1–100,000 to change campaign length. A failure identifies
the iteration and seed. Add a minimized reproducer as a regression before fixing
the underlying problem. This is mutation testing, not coverage-guided fuzzing.

The suite covers malformed UTF-8 and control sequences, forged integration
reports, clipboard requests, query floods, oversized OSC strings, resize during
incomplete output, and one-row scrollback pruning. UI tests additionally check
the private pasteboard, literal hostile filename completion, and shared history
privacy across panes. The PTY test explicitly duplicates an inheritable descriptor
above 255 and checks that an executed interpreter cannot access it, while retaining
a controlling PTY on descriptors 0–2. The test wrapper raises the soft descriptor
limit before starting Swift so this regression can run on Macs that default to 256.
It selects the extra Testing framework paths only for Command Line Tools;
full-Xcode installations, including GitHub runners, use SwiftPM's normal setup.

AddressSanitizer instruments the Swift code and C shim in the fuzz build. The Zig
static library is built with `ReleaseSafe`; it is not AddressSanitizer-instrumented
by SwiftPM. Parser coverage instrumentation, coverage-guided fuzzing, longer
campaigns, sustained resize/output stress, and measured peak-memory budgets
remain follow-up work. CI has an overall job timeout; the flood regression checks
completion and continued usability, not a proven global resource bound.

## Release and benchmark builds

Release Swift targets use SwiftPM's normal checked optimization. Ghostty defaults
to `ReleaseSafe`, and packaging explicitly selects that mode. Packaging uses a
fresh `.build/package` directory so SwiftPM cannot reuse an executable previously
linked against a different external Ghostty archive. The library build key includes
the commit, Zig version, optimization mode, operating system, and architecture.

Automation environment variables are compiled into debug builds or builds made
with `-Xswiftc -DREWARP_TESTING`. `scripts/bench.sh` uses this flag in a separate
`.build/bench` directory. Normal release builds exclude command submission,
control-channel input, capture activation, and timing-file activation. The release
check inspects the binary and launches it with automation variables set to verify
that they cannot execute a command, open a FIFO, write files, or terminate the app.

Run `make bench MB=256 KIND=scroll` and `make bench MB=256 KIND=repaint` on the
same Mac used for the baseline before updating performance claims. No macOS
performance claim is inferred from unit-test timings. The pull-request release
benchmark workflow compares three 256 MiB scroll and repaint runs for the base
and head on the same macOS runner, and records medians in its job summary. This
measures the complete hardening change, including both Swift and Zig optimization
modes; it does not isolate Swift bounds-check overhead. Hosted-runner numbers
should be followed by measurements on the user's Mac before changing product
performance claims.

A leading ASCII space opts a new submission out of Rewarp's in-memory history
before trimming. The original command is still sent to the shell. This conservative
rule is independent of shell options. It does not erase existing imported shell
history, commands shown in terminal blocks, process arguments, or output.

## GitHub Actions and CodeQL

`.github/workflows/security.yml` runs macOS debug/release tests, UI security
regressions, production automation checks, sanitizer mutation testing, and Gitleaks.
Scheduled runs increase the mutation count. Actions use reviewed commit pins;
Dependabot checks GitHub Actions weekly.

CodeQL uses a manual macOS build with both `swift` and `c-cpp` extractors. Ghostty
is built before extraction. A fresh SwiftPM scratch directory ensures that both
Swift and the C shim actually compile during extraction. Zig is outside CodeQL
coverage. Do not restore compiled Swift targets into this build directory.

The repository was private when setup was inspected. CodeQL runs automatically
for public repositories. For an eligible private repository with Code Security
enabled, set the repository variable `CODEQL_ENABLED=true`. This flag does not
purchase or enable a subscription. GitHub's eligibility rules are documented in
[CodeQL setup](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages).

Schedules only run from the default branch. After the first successful runs,
select the test/scan checks in branch protection as appropriate.

## SonarQube Cloud

The Swift-only project configuration is in `sonar-project.properties`. This avoids
claiming C coverage without Sonar's C build configuration. CodeQL covers the C
shim, and neither analyzer covers the Zig parser.

To activate the prepared Sonar job:

1. Import the repository into SonarQube Cloud and select an eligible plan.
2. Disable Automatic Analysis for this project when enabling CI-based analysis.
3. Set repository variables `SONAR_ORGANIZATION` and `SONAR_PROJECT_KEY` using
   the identifiers assigned by Sonar.
4. Store its analysis token as the Actions secret `SONAR_TOKEN`.
5. Run the Security workflow and inspect the first analysis and quality gate.

The job stays disabled until both identifiers are configured and skips fork PRs
because their workflows cannot access the token. There is no zero-coverage gate
configuration here: code coverage reports are not yet exported to Sonar.

The dedicated [OSS plan](https://docs.sonarsource.com/sonarqube-cloud/administering-sonarcloud/managing-subscription/subscription-plans#oss-plan)
is for public open-source projects. Rewarp is MIT-licensed, but the repository
must also be public to use that offering. Sonar also
offers a separate Free plan for private projects up to 50,000 lines, with more
limited analysis features. Review the applicable plan before activation. GitHub's
free public-repository scanning eligibility depends on public visibility, not on
the presence of an open-source license.

## Secrets

Run `make secrets` from a non-shallow clone. It scans all locally fetched refs and
the working tree with redacted Gitleaks output. The Linux x86_64 bootstrap uses a
checksum-pinned Gitleaks release; elsewhere install Gitleaks first. CI fetches
full history. Fetch every remote branch/tag before a pre-publication audit and
audit external artifacts separately.

On 2026-11-06, Gitleaks 8.30.1 reported no leaks in the available non-shallow local
history (11 commits scanned) or working tree. This does not cover unfetched refs,
GitHub issues, attachments, artifacts, credentials outside the repository, or all
possible secret formats. Repeat immediately before any visibility change.

GitHub secret scanning and push protection require repository settings. Enable
them under Settings → Code security when the repository is eligible, then inspect
the historical alerts. A local Gitleaks scan does not activate GitHub push
protection.

## Ghostty monitoring

`scripts/ghostty-version.env` holds the reviewed commit and Zig version. The daily
Ghostty workflow compares the pin with upstream and checks every published
repository advisory, failing for unreviewed advisories or a diverged pin. New
upstream commits produce a warning and comparison link; they are not merged
automatically. API/network failures fail the job instead of looking like a clean
advisory feed.

`security/ghostty-advisory-reviews.json` records the 18 advisory reviews from
2026-11-06. The four advisories naming libghostty-vt have fixes that are ancestors
of the current pin. The remaining advisories list patched Ghostty releases no
later than v1.4.0, which is also an ancestor. This says those upstream fixes are
included; it does not establish that Rewarp's independently implemented app,
shell integration, paste handling, or PTY launcher have equivalent protection.

Each review records the pin, upstream advisory update timestamp, rationale, fix
commit, and comparison URL. A changed advisory or dependency pin invalidates the
review. Before recording a new review, read its impact and verify fix ancestry or
document why the affected feature is outside Rewarp's build. For dependency
updates, also review the C API, update Zig/checksums if necessary, rebuild, rerun
the macOS suite and fuzz campaign, and benchmark before shipping.

## Independent audit

[security-audit-brief.md](security-audit-brief.md) is a prepared brief for an OSTIF
funding request or auditor intake. It has not been submitted. An audit engagement,
funding application, and publication of findings remain owner decisions.
