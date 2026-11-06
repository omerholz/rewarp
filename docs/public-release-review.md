# Public release review

Review date: 2026-11-06. Scope: the working tree based on the app implementation
in `initial-app`, all 10 original commits reachable from the local refs, and
the three corresponding branch heads on GitHub. The default remote branch,
`main`, still contains only the original initial commit. The GitHub repository
remains private. A fresh snapshot was pushed to the temporary
`public-release-review` branch to run CI; existing branches, the default branch,
and visibility were not changed.

## Assessment

The source has been prepared for a public release with MIT licensing and a
reproducible fresh-history export. No credential was found. **All 168 unit tests,
147 GUI tests, release app checks and secret scans pass. The maintainer chose
preparation only; GitHub publication is left to them.** This
was a source review with targeted checks, not a penetration test or a certification
of the application or its dependencies.

## Findings addressed

| Finding | Impact | Change |
| --- | --- | --- |
| No project license | Readers had no explicit permission to use, modify, or redistribute the code | Added the maintainer-selected MIT license and contributor guidance |
| Missing dependency notices in app bundles | Binary redistribution omitted Ghostty's MIT notice and notices for statically linked code | Added pinned upstream licenses, dependency inventory and notices; `bundle.sh` copies them into the app |
| Swift `-Ounchecked` and Zig `ReleaseFast` | Release builds disabled runtime checks while processing untrusted terminal data | Restored standard Swift optimization and switched Ghostty to `ReleaseSafe`; dependency cache stamp now includes build mode and checks the archive exists |
| Child descriptor cleanup stopped at 255 | Files and sockets above that range could leak into shells/commands | Capture the process descriptor limit before `forkpty` and close the full range in the child; added a regression test |
| `waitpid` did not retry interruptions | A signal could leave the shell unreaped and report an invalid exit status | Retry `EINTR` |
| Empty stream reads could access byte zero while awaiting a string terminator | A zero-length input buffer could cause an invalid read and consume pending parser state | Return immediately for empty input; added a regression test |
| Automation environment reached child shells | Nested app launches could reuse a control FIFO, rerun a command, or write a capture unexpectedly | Remove inherited `REWARP_*` values before adding the pane's integration values; isolate the e2e harness, visual helper and benchmark environments; added a launch regression test |
| Work email in initial commit metadata | Making the original Git history public would disclose it | Prepared a fresh-history export using a GitHub noreply identity; the original repository is preserved |
| Public contributor/security/release guidance missing | New users lacked a supported development and reporting path | Added contribution, security and release guides, expanded README, removed unsupported license claims about Warp and marked old performance data as historical |
| No automated checks | Regressions and credential commits could reach the default branch unnoticed | Added read-only CI for full-history Gitleaks, script syntax, macOS unit tests and app packaging; tools are pinned and checksum-verified |
| Unit-test wrapper accepted zero executed tests | An unmatched filter could report success without testing anything | Require a nonzero Swift Testing test count and fail if the initial directory change fails |
| GUI tests assumed the developer's login shell was zsh | On other accounts every integration-dependent GUI test could time out at startup | Default the e2e harness explicitly to `/bin/zsh`, preserve requested alternate shells, and probe startup before the full CI suite |
| GUI tests hard-coded Retina scaling and character dimensions | Several checks failed on the hosted runner's display | Expose actual cell dimensions/backing scale in debug state, use them for hit coordinates and viewport checks, and retain the tall-output regression above 70,000 device pixels at scale 1 |
| Filter-selection regression raced against moving output | The test could miss the row before it even created a selection | Hold the command at `read`, wait for stable layout, and require the exact selection to survive the refresh while the block remains running |
| Maintainer governance was implicit | Contributors and future setup lacked an explicit owner-controlled PR policy | Added CODEOWNERS, contributor policy, branch/tag ruleset templates and a setup command; verified current sole-writer access and workflow permissions; plan-limited activation is documented below |

The old history remains in the original private repository. The new export has
no remote, old refs, tags, or commit ancestry. Reusing the original GitHub
repository requires further cleanup because other branches and PR references
can keep that history reachable. A new repository avoids carrying those records
into the public destination. See [releasing](releasing.md).

A separate `add-chatgpt-app-icons` branch appeared during the final remote
inventory. It is outside this prepared snapshot and was left unchanged. Recheck
the remote inventory when publishing; the export covers this reviewed source.

## Checks completed here

- Gitleaks 8.30.1, downloaded from its official release and SHA-256 verified:
  no findings in reachable history (`--all --full-history`), source, or commit
  messages. Gitleaks reports nine scanned non-merge commits; Git counts ten
  commits including the merge. The initial 170 local reachable objects pass
  `git fsck`.
- Reviewed historical filenames, identities, and current source for credentials,
  personal paths, private service endpoints and data files. The original tree
  has 67 tracked text files and no tracked dependency archives, recordings,
  credentials or binary app artifacts. The work email is a metadata finding,
  not a credential; it need not appear in the public snapshot.
- Reviewed shell quoting/completion, paste encoding, private OSC routing, token
  handoff, shell startup, local automation, PTY lifecycle, render buffer use,
  build/download scripts and packaging. Existing tests cover spoofed reports,
  tokens not reaching command environments, quoting, and shell replacement.
- Compared the original three GitHub branch heads to the local refs. GitHub
  metadata reports a private repository, no tags, releases, Actions artifacts,
  wiki, Pages site, or discussions. Reviewed the sole PR's description; it has
  no issue or review comments and no attachments. Only CI runs added during
  this review appear in the Actions run inventory. GitHub's hidden PR refs and
  cached old commits still require consideration if reusing this repository.
- Confirmed the Zig requirement, upstream MIT/font licenses and linked dependency
  list against the pinned Ghostty revision. Copied linked-code notices from
  its exact dependency archives and vendored simdutf source. The inventory is
  upstream's cross-target list, not a measured binary SBOM.
- The C PTY test compiles with warnings as errors on Linux using a compatibility
  header for `forkpty`. It proves descriptor 300 reaches the child with the old
  launcher (exit 42), and is closed with the changed launcher (exit 0). This
  exercises the C logic; it does not validate Darwin behavior or Swift bridging.
- Shell syntax, Python syntax, whitespace, fresh-export structure/content,
  documentation links, and packaging notice copy checks passed locally.
  The local packaging check used stub build/signing tools.
- A mocked launch check confirms that the visual helper uses a private HOME,
  temporary directory and history file, and drops inherited automation and
  ZDOTDIR. The original helper created a temporary directory but did not use it
  as HOME; benchmarks also now drop an inherited ZDOTDIR and automation settings.
- ShellCheck 0.11.0 and actionlint 1.7.12 pass. Mocked test-runner checks confirm
  zero tests fail, nonzero passing tests succeed, and Swift failures propagate.
- A mocked e2e launch confirms the harness selects zsh independently of inherited
  settings, preserves an explicit bash override, and isolates HOME and ZDOTDIR.
- The exporter was tested with inherited private author/committer email settings:
  both identities in the new root commit still use the GitHub noreply address.
- [Final private CI run](https://github.com/omerholz/rewarp/actions/runs/42162550491)
  passed on macOS 15 (arm64, Swift 6.1.2, Zig 0.17.0): all 168 unit tests,
  all 147 GUI end-to-end tests, zsh syntax, the release app build,
  `codesign --verify --deep --strict`, and exact copying of the license directory.
  The independent Linux job passed full-history/source Gitleaks and script checks.
  This confirms a real macOS build and signature check in addition to the local
  packaging simulation. These checks ran against the fresh snapshot on
  `public-release-review`; subsequent report edits do not change the tested code.
- [Governance follow-up CI](https://github.com/omerholz/rewarp/actions/runs/42227730330)
  passes seven safety tests, the history/source secret scan, 168 app unit tests
  and release app checks. The safety tests cover idempotency, platform
  defaults, read-only inspection, sole-owner access and preservation of visibility,
  collaborators and unrelated rulesets. Live verification confirms @omerholz is
  the only collaborator with write access, auto-merge is off, workflow defaults
  are read-only, and workflows cannot approve PRs. Rulesets are blocked by the
  current private-repository plan, and fork contributor approval is a public-only
  API. Their JSON templates are prepared but **not active**. See
  [governance](governance.md) for activation and account-security checks.

## Remaining maintainer steps

1. Use the reviewed fresh snapshot for publication. The original private
   repository and its history are preserved; the temporary review branch exists
   only to validate and inspect the changes. The export contains 96 source,
   documentation and license files, one root commit on `main`, and no remotes.
2. CI uses macOS 15. The advertised macOS 14 minimum has not been validated in
   this review; the README discloses that limit. Before a binary release,
   smoke-test Finder launch, validate the minimum OS, and complete Developer ID
   signing/notarization. Source publication does not need signing credentials.
3. Confirm rights to release the source and assets, including any applicable
   employment obligations. The historical documentation states independent
   implementation from public behavior, but that statement alone is not proof
   of provenance. The review removed categorical claims about Warp's licensing.
4. Choose the destination, review the fresh snapshot and remote metadata while
   private, set the default branch to the fresh `main`, and enable the available
   security settings. Enable GitHub private vulnerability reporting when public.
   Do not publish old branches, tags, logs or backups accidentally.

## Known limits appropriate to disclose

- The project is experimental (0.0.1), supports macOS only, and has zsh-only
  block integration. Other shells are plain terminals. Session restore,
  settings and several parity items remain unfinished.
- Blocks retain up to 50,000 rows each, but total session memory is not capped.
  Find/filter regexes run on the main thread under the session lock and can
  stall on large or adversarial data. Resource exhaustion remains possible.
- The shell token authenticates printed reports against output-only spoofing;
  it does not isolate malicious shell code or same-user processes. Plain shells
  accept spoofable OSC 7 directory reports. The app is not sandboxed.
- Local automation is active only when launch environment variables request it;
  those interfaces can read terminal state, inject input, and write files. They
  are documented in `SECURITY.md` and must only be configured by trusted code.
- Packaging is ad hoc signed for local use, host-architecture only, without
  Developer ID signing or notarization. Those are binary-release requirements,
  not prerequisites for publishing source.
- Historical benchmarks predate the safety-check changes and lack enough
  hardware/toolchain detail to establish current performance. Remeasure before
  claiming parity or a speed advantage.

These limits can be disclosed for an experimental source release. They should
not be represented as solved, tested on all Macs, or production-ready.
