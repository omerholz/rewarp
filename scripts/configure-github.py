#!/usr/bin/env python3
"""Check/apply Rewarp's GitHub governance; never changes visibility or access.

Usage: python3 scripts/configure-github.py OWNER/REPO [--apply]
Exit 0 means compliant, 1 means drift/error, and 2 means a requested protection
is unavailable on the current repo/plan.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MAINTAINER = "omerholz"


class APIError(RuntimeError):
    def __init__(self, payload, detail):
        # With --paginate --slurp, gh may emit [] instead of the error body.
        # Its diagnostic still includes the HTTP status.
        http_status = re.search(r"\(HTTP (\d{3})\)", detail)
        self.status = str(payload.get("status") or (http_status.group(1) if http_status else ""))
        super().__init__(payload.get("message") or detail or "GitHub API failed")


def policy_matches(actual, expected):
    """Compare requested policy fields, ignoring API defaults and array order."""
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(
            key in actual and policy_matches(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            return False
        remaining = list(actual)
        for item in expected:
            match = next((index for index, value in enumerate(remaining)
                          if policy_matches(value, item)), None)
            if match is None:
                return False
            remaining.pop(match)
        return True
    return actual == expected


def api(endpoint, method="GET", payload=None, paginate=False):
    command = ["gh", "api", "--hostname", "github.com", "--method", method,
               "-H", "X-GitHub-Api-Version: 2026-03-10", endpoint]
    if paginate:
        command += ["--paginate", "--slurp"]
    if payload is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            capture_output=True, text=True)
    try:
        data = json.loads(result.stdout) if result.stdout.strip() else None
    except json.JSONDecodeError:
        data = None
    if result.returncode:
        raise APIError(data if isinstance(data, dict) else {}, result.stderr.strip())
    return [item for page in data for item in page] if paginate else data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", help="Personal repository owned by omerholz, as OWNER/REPO")
    parser.add_argument("--apply", action="store_true", help="Apply and verify the supported settings")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", args.repository):
        parser.error("repository must be OWNER/REPO")

    base = "repos/" + args.repository
    repo = api(base)
    actor = api("user")["login"]
    if (repo["owner"]["type"] != "User" or
            repo["owner"]["login"].lower() != MAINTAINER or actor.lower() != MAINTAINER):
        raise RuntimeError("Run as omerholz against a personal repository owned by omerholz.")
    if not repo.get("permissions", {}).get("admin"):
        raise RuntimeError("Repository administration permission is required.")
    if repo["default_branch"] != "main":
        raise RuntimeError("Set the reviewed main branch as the default before applying this policy.")
    collaborators = api(base + "/collaborators?per_page=100", paginate=True)
    other_writers = [entry["login"] for entry in collaborators
                     if entry["login"].lower() != MAINTAINER and
                     any(entry.get("permissions", {}).get(level) for level in ("push", "maintain", "admin"))]
    if other_writers:
        raise RuntimeError("Review existing write access before proceeding: " + ", ".join(other_writers))
    print("Verified: omerholz is the only collaborator with write access.")

    policies = [
        (base, "PATCH", {"allow_auto_merge": False}),
        (base + "/actions/permissions/workflow", "PUT",
         {"default_workflow_permissions": "read", "can_approve_pull_request_reviews": False}),
    ]
    pending = []
    drift = False
    for endpoint, method, desired in policies:
        current = api(endpoint)
        if args.apply and any(current.get(key) != value for key, value in desired.items()):
            api(endpoint, method, desired)
            current = api(endpoint)
        matches = all(current.get(key) == value for key, value in desired.items())
        print(("Verified" if matches else "Would set") + ": " + json.dumps(desired))
        drift |= not matches
        if args.apply and not matches:
            raise RuntimeError("GitHub did not retain the requested policy: " + endpoint)

    endpoint = base + "/actions/permissions/fork-pr-contributor-approval"
    desired = {"approval_policy": "all_external_contributors"}
    if repo["private"]:
        pending.append("Fork workflow approval: configure on the public destination; this API is public-only.")
    else:
        current = api(endpoint)
        if args.apply and current.get("approval_policy") != desired["approval_policy"]:
            api(endpoint, "PUT", desired)
            current = api(endpoint)
        matches = current.get("approval_policy") == desired["approval_policy"]
        print(("Verified" if matches else "Would set") + ": " + json.dumps(desired))
        drift |= not matches
        if args.apply and not matches:
            raise RuntimeError("GitHub did not retain the fork workflow approval policy.")

    try:
        existing = api(base + "/rulesets?includes_parents=false", paginate=True)
    except APIError as error:
        if error.status != "403" or "Upgrade to GitHub Pro or make this repository public" not in str(error):
            raise
        pending.append("Branch and tag rules: " + str(error))
        existing = None

    if existing is not None:
        for filename in ("main.json", "releases.json"):
            desired = json.loads((ROOT / ".github" / "rulesets" / filename).read_text())
            matches = [rule for rule in existing if rule["name"] == desired["name"]]
            if len(matches) > 1:
                raise RuntimeError("Duplicate ruleset names require review: " + desired["name"])
            endpoint = base + "/rulesets" + ("/" + str(matches[0]["id"]) if matches else "")
            current = api(endpoint) if matches else {}
            correct = policy_matches(current, desired)
            if args.apply and not correct:
                saved = api(endpoint, "PUT" if matches else "POST", desired)
                current = api(base + "/rulesets/" + str(saved["id"]))
                correct = policy_matches(current, desired)
            print(("Verified" if correct else "Would apply") + ": " + desired["name"])
            drift |= not correct
            if args.apply and not correct:
                raise RuntimeError("GitHub did not retain the ruleset: " + desired["name"])

    for message in pending:
        print("Pending: " + message)
    print("Visibility and collaborator access were not changed.")
    return 2 if pending else int(drift)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (APIError, RuntimeError, OSError, ValueError) as error:
        print("error: " + str(error), file=sys.stderr)
        sys.exit(1)
