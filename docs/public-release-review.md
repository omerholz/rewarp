# Public release review

Review date: 2026-11-06. This release-readiness work builds on the terminal
security hardening in [PR #3](https://github.com/omerholz/rewarp/pull/3), including
its MIT license, checked release optimization, descriptor isolation, production
automation isolation, and security regression suite. The app icon changes are
preserved. The repository remains private; publication is the maintainer's task.

## Changes in this follow-up

- Include the pinned Ghostty dependency inventory, linked-code licenses and font
  notices in `LICENSES/`, and copy those notices into app bundles. Keep the
  security PR's package build directory and production automation checks.
- Ignore local credentials, signing material, editor state and generated output.
  Scan fetched Git history and tracked/untracked non-ignored source, without
  following symlinks into files outside the checkout.
- Ignore empty parser reads without consuming pending string-terminator state;
  retry interrupted child-process waits; remove inherited automation variables
  from pane shells and isolate visual-test/benchmark environments.
- Make GUI tests use actual backing scale and cell dimensions, and keep the tall
  output test above 70,000 device pixels on non-Retina displays. Stabilize the
  filter-selection test while still checking exact selection across a refresh.
- Reject unit-test invocations that execute zero tests. Reuse the security PR's
  pinned dependency setup and scanner instead of maintaining duplicate tooling.
- Document development, security boundaries, third-party licenses, maintainer
  governance and release preparation. Remove unsupported claims about Warp's
  license and mark pre-safety-check benchmarks as historical.
- Provide a fresh-history export with GitHub noreply identities. The export has
  one root commit on `main`, no remotes and no original commit ancestry.

The security PR already closes descriptors beyond the soft limit and raises the
limit before starting Swift tests. This follow-up preserves those implementations
and avoids a duplicate test that changes process-wide limits while suites run.

## Validation

The pre-integration snapshot passed 168 Swift unit tests, 147 GUI tests, app
build/signature checks, source/history secret scans, and seven governance-tool
safety tests. The combined branch is validated again in this PR's CI; see its
checks for results against the final code, including the security PR's tests.
Local checks cover shell/workflow lint, Python tooling, source export identities,
bundle cloning, license inventory, documentation links and whitespace.

Gitleaks found no credential in the audited original history or prepared source.
A work email in the original first commit is private metadata, so the maintainer
chose a fresh initial commit for publication. This is source review and targeted
validation, not a certification of all code or dependencies. The dependency
inventory is upstream's cross-target list, not a measured binary SBOM.

## Governance status

`CODEOWNERS` and the contribution policy identify @omerholz as maintainer. Live
verification confirmed sole-collaborator write access, disabled auto-merge, and
read-only workflow defaults with workflow PR approval disabled.

The branch/tag rulesets are prepared but **not active**: GitHub rejects them on
the current private repository's plan. The all-external-contributor workflow
approval API is public-only. [The setup command](governance.md) can apply and
verify them on the public destination. It does not change visibility, subscription
or collaborator access. Account authentication and integration access remain
owner checks.

## Before publication

1. Confirm rights to release contributions and assets. The project's stated
   approach is independent implementation from public documentation; that alone
   does not prove provenance or resolve any employment obligations.
2. Recreate and inspect the fresh export after the reviewed changes land. Review
   files, author/committer identities, refs and GitHub metadata before publishing.
   Old branches, PR references, cached commits, logs and attachments can retain
   history if the existing repository is reused. Keep private backups private.
3. Run the governance setup against the actual public destination and verify its
   protections. Enable private vulnerability reporting and available secret
   scanning/push protection there. No repository was made public by this work.
4. For a binary release, complete Developer ID signing/notarization and test a
   quarantined download and Finder launch on another Mac. The deployment target
   is macOS 14; automated validation uses macOS 15. See [releasing](releasing.md).

## Known limits

Rewarp is experimental (0.0.1), macOS-only, with zsh block integration. Other
shells are plain terminals. Total session memory is uncapped; main-thread regex
find/filter can stall on large or adversarial inputs. Shell tokens protect
against output-only report spoofing, not malicious shell code or same-user
processes. The app is not sandboxed. Session restore and other parity features
remain unfinished. Historical performance needs remeasurement with checked
release builds. See [SECURITY.md](../SECURITY.md) and
[known limits](design.md#known-limits).
