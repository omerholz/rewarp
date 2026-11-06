# Repository ownership and contributions

Rewarp is maintained by **@omerholz**, who decides what is accepted into the
upstream repository and what becomes an official release. Contributors work in
their own forks and open pull requests. Public visibility does not grant write
or merge access. The MIT license permits independent reuse and distribution;
it does not grant control over this GitHub repository.

`.github/CODEOWNERS` requests the maintainer's review for incoming changes.
Access settings and active rulesets enforce permissions. The sole-maintainer
policy requires a PR but zero approval reviews, so the maintainer can merge
their own PRs. Required code-owner approval and last-push approval stay off;
GitHub does not allow authors to approve their own PRs.

## Desired GitHub configuration

| Setting | Policy |
| --- | --- |
| Human write access | Only @omerholz |
| Main branch | Require PRs and resolved review conversations |
| Approval count | Zero while there is one maintainer |
| CI | Require `secrets` and `macos` from the GitHub Actions app; branch must be up to date |
| Main force pushes/deletion | Blocked, with no routine bypass actors |
| Release tags | `v*` tags can be created, but cannot be updated or deleted |
| Auto-merge | Off |
| Default workflow permissions | Read-only; Actions cannot approve PRs |
| Public fork PR workflows | Maintainer approval for every external contributor |

Review the code and workflows before approving an outside workflow run. Keep
release credentials out of PR jobs and run untrusted PR code on GitHub-hosted
runners. Review GitHub Apps, deploy keys and tokens separately: an integration
you authorize can act with its granted permissions. Use account 2FA/passkeys
or security keys and retain recovery codes; the repository setup command does
not enroll authentication factors or revoke account credentials.

## Check or apply the policy

The JSON files in [`.github/rulesets`](../.github/rulesets) are configuration
templates. **Committing them does not activate GitHub protections.**

Install the GitHub CLI and authenticate as @omerholz with repository admin
access. Use the publication destination's `OWNER/REPO`, including a different
repository name if the old repository is kept private:

```sh
# Inspect without changing settings.
python3 scripts/configure-github.py omerholz/rewarp

# Apply supported settings, then read them back to verify.
python3 scripts/configure-github.py omerholz/rewarp --apply
```

Run this after pushing the reviewed `main`, setting it as the default branch,
and completing its first CI run. The command verifies sole-maintainer write
access, keeps visibility and collaborator access unchanged, disables auto-merge,
sets workflow permissions, configures public fork approvals, and creates or
updates only the two rulesets named in the templates. It preserves other
rulesets. It refuses another owner, another default branch or additional writers
so that access changes can be reviewed deliberately.

Exit codes: `0` means compliant, `1` means drift or an error, and `2` means a
requested feature is unavailable. It applies supported settings even if another
feature is unavailable. A second application makes no changes when compliant.

The current private `omerholz/rewarp` repository's plan rejects rulesets, and
GitHub's fork-approval API is public-only. They remain pending while this repo is
private. Branch/tag rulesets are available on GitHub Free for public repositories.
The command does not publish the repository or change its subscription. Run it
again on the public destination to activate and verify these protections.

When adding another maintainer, revisit collaborator roles and required reviews.
Keep the owner in control of changes to the governance policy and release access.

## References

- [Personal repository permissions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/permission-levels-for-a-personal-account-repository)
- [Rulesets and plan availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [Actions permissions API](https://docs.github.com/en/rest/actions/permissions)
- [GitHub Actions security guidance](https://docs.github.com/en/actions/reference/security/secure-use)
