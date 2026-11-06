# Preparing a public release

This repository's first public release should use a fresh initial commit, as
chosen by the maintainer. The old repository has a work email in its first
commit; no credential was found in the audited Git history. Do not copy the old
`.git` directory into the public repository.

## Validate the source

On a Mac with the documented toolchain, run:

```sh
make secrets
make check
make package
codesign --verify --deep --strict dist/Rewarp.app
```

Run GUI tests in a logged-in graphical session with Metal. CI runs unit tests
and builds the app; its optional GUI run does not replace local testing.
Smoke-test a fresh clone, a packaged app launched from Finder, Unicode input,
paste, `exec zsh`, a plain bash session, tab/pane closing, and a full-screen
program. Review the [publication review](public-release-review.md) for outstanding
work. Benchmark again after changes to safety checks; old results are historical.

Verify that you own or have permission to release all contributions and that no
employer or customer code/assets were incorporated. The MIT license covers
Rewarp code; third-party notices must remain with their dependencies.

## Prepare a fresh history

From the reviewed working tree:

```sh
scripts/prepare-public.sh /tmp/rewarp-public
cd /tmp/rewarp-public
make secrets
git log --all --format=fuller
git ls-files
git remote -v
```

The script copies tracked files and untracked, non-ignored files, excluding
deleted files, then creates one commit on `main` with the maintainer's GitHub
noreply address. Inspect the export; untracked files must also be reviewed.
It refuses existing destinations and paths inside the source tree. It creates
no remote and does not alter the original repository or push anything.

Check there is exactly one commit, one branch, no tags, no old objects, and no
private information in files, messages, author/committer identities, or the
generated app. Recreate the export if the source changes after preparation.

## Choose the GitHub destination

The cleanest separation is a **new private GitHub repository**, initially
without an auto-generated README/license, then push only the reviewed `main`:

```sh
git remote add origin <new-private-repository-url>
git push -u origin main
```

Run CI there while it is private. Set `main` as the default branch. Apply and
verify the [maintainer governance policy](governance.md):

```sh
python3 scripts/configure-github.py <owner>/<publication-repo> --apply
```

The command keeps visibility and write access unchanged. On the current private
repo's plan, branch/tag rulesets remain unavailable; public fork workflow approval
also needs a public repository. Rerun the command after publication to activate
those protections on the public destination. Enable private vulnerability
reporting, secret scanning and push protection where available. Keep workflow
permissions read-only and PR jobs separate from release credentials.

If reusing `omerholz/rewarp`, replacing `main` alone is insufficient: existing
`initial-app` and `claude/sad-hawking-32a293` branches and PR #1 refer to the old
history. Inventory remote heads, tags, pull requests, Actions logs/artifacts,
releases, issues, wiki and attachments before changing visibility. Remove obsolete
branches/tags deliberately and coordinate any force push. Preserve a private
backup first; do not publish the backup or use `git push --mirror`.

GitHub can retain old commits via pull request references and cached views even
after a force push. A fresh commit in the same repository does not promise
erasure of those records. See GitHub's
[sensitive-data removal guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
If a credential is ever found, revoke/rotate it before treating history cleanup
as remediation.

Review the actual GitHub repository contents, metadata, CI results and security
settings while private, then change visibility to public. Source publication
does not require a Developer ID certificate or notarization.

## Distribute binaries

`make package` produces an ad hoc signed app for local development. It is not a
notarized download for other users. Before a public binary release:

1. Verify `Contents/Resources` includes the Rewarp license, third-party notices,
   all of `LICENSES/`, the font and its OFL notice, and shell integration files.
2. Sign with a Developer ID Application identity and hardened runtime, then
   notarize and staple using Apple's current distribution tools. Keep signing
   credentials outside Git; review needed entitlements before signing.
3. Test the downloaded, quarantined artifact on another Mac, including Gatekeeper
   verification, Finder launch and shell integration. State CPU architecture and
   macOS requirements; the build script builds for the host, not a universal app.
4. Attach the tested artifacts, checksums, source revision, release notes and
   known limitations. Do not upload `.build`, `vendor`, test captures or logs.

Consult Apple's current
[distribution guide](https://developer.apple.com/documentation/security/distributing-your-app-for-testing-and-production)
when setting up signing; the repository does not automate Developer ID signing
or notarization yet.
