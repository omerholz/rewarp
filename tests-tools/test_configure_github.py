"""Exercise governance changes without granting access or publishing a repo."""

import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "configure_github", Path(__file__).resolve().parents[1] / "scripts/configure-github.py")
governance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(governance)
BASE = "repos/omerholz/rewarp"


class GitHub:
    def __init__(self, private=False):
        self.repo = {"private": private, "default_branch": "main", "allow_auto_merge": True,
                     "owner": {"type": "User", "login": "omerholz"}, "permissions": {"admin": True}}
        self.actor = "omerholz"
        self.collaborators = [{"login": "omerholz", "permissions": {"admin": True, "push": True}}]
        self.workflow = {"default_workflow_permissions": "write", "can_approve_pull_request_reviews": True}
        self.approval = {"approval_policy": "first_time_contributors"}
        self.rules = {10: {"id": 10, "name": "Unrelated policy", "rules": []}}
        self.writes = []

    def api(self, endpoint, method="GET", payload=None, paginate=False):
        if method != "GET":
            self.writes.append((endpoint, method, copy.deepcopy(payload)))
        if endpoint == "user":
            return {"login": self.actor}
        if endpoint == BASE:
            if payload:
                self.repo.update(payload)
            return copy.deepcopy(self.repo)
        if endpoint.startswith(BASE + "/collaborators"):
            assert method == "GET", "collaborator access must never be modified"
            return copy.deepcopy(self.collaborators)
        for suffix, state in [("workflow", self.workflow),
                              ("fork-pr-contributor-approval", self.approval)]:
            if endpoint == BASE + "/actions/permissions/" + suffix:
                if payload:
                    state.update(payload)
                return copy.deepcopy(state)
        if endpoint == BASE + "/rulesets?includes_parents=false":
            if self.repo["private"]:
                raise governance.APIError(
                    {"status": "403", "message":
                     "Upgrade to GitHub Pro or make this repository public to enable this feature."}, "")
            return [{"id": key, "name": value["name"]} for key, value in self.rules.items()]
        if endpoint.startswith(BASE + "/rulesets"):
            rule_id = int(endpoint.rsplit("/", 1)[1]) if endpoint.rsplit("/", 1)[1].isdigit() else None
            if payload:
                rule_id = rule_id or max(self.rules) + 1
                saved = copy.deepcopy(payload)
                saved["id"] = rule_id
                # GitHub returns defaults and may reorder rule/check lists.
                saved["rules"].reverse()
                for rule in saved["rules"]:
                    if rule["type"] == "required_status_checks":
                        rule["parameters"]["do_not_enforce_on_create"] = False
                        rule["parameters"]["required_status_checks"].reverse()
                self.rules[rule_id] = saved
            return copy.deepcopy(self.rules[rule_id])
        raise AssertionError("Unexpected API call: " + endpoint)


def run(github, apply=True):
    args = ["configure-github.py", "omerholz/rewarp"] + (["--apply"] if apply else [])
    with patch.object(sys, "argv", args), patch.object(governance, "api", side_effect=github.api), \
            contextlib.redirect_stdout(io.StringIO()):
        return governance.main()


class GovernanceTests(unittest.TestCase):
    def test_paginated_cli_plan_error_retains_http_status(self):
        result = subprocess.CompletedProcess([], 1, "[]\n",
                    "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)")
        with patch.object(governance.subprocess, "run", return_value=result):
            with self.assertRaises(governance.APIError) as error:
                governance.api(BASE + "/rulesets", paginate=True)
        self.assertEqual(error.exception.status, "403")

    def test_public_setup_is_idempotent_and_preserves_visibility_access_and_other_rules(self):
        github = GitHub()
        original_access = copy.deepcopy(github.collaborators)
        self.assertEqual(run(github), 0)
        self.assertFalse(github.repo["private"])
        self.assertEqual(github.collaborators, original_access)
        self.assertEqual(github.rules[10], {"id": 10, "name": "Unrelated policy", "rules": []})
        self.assertFalse(github.repo["allow_auto_merge"])
        self.assertEqual(github.workflow, {"default_workflow_permissions": "read",
                                         "can_approve_pull_request_reviews": False})
        self.assertEqual(github.approval["approval_policy"], "all_external_contributors")
        main = next(value for value in github.rules.values() if value.get("target") == "branch")
        rules = {rule["type"]: rule for rule in main["rules"]}
        self.assertEqual(rules["pull_request"]["parameters"]["required_approving_review_count"], 0)
        self.assertFalse(rules["pull_request"]["parameters"]["require_code_owner_review"])
        self.assertEqual({check["integration_id"] for check in
                          rules["required_status_checks"]["parameters"]["required_status_checks"]}, {15368})
        self.assertEqual(main["bypass_actors"], [])
        tags = next(value for value in github.rules.values() if value.get("target") == "tag")
        self.assertEqual({rule["type"] for rule in tags["rules"]}, {"update", "deletion"})
        github.writes.clear()
        self.assertEqual(run(github), 0)
        self.assertEqual(github.writes, [])

    def test_private_repo_applies_supported_settings_and_reports_plan_limit(self):
        github = GitHub(private=True)
        self.assertEqual(run(github), 2)
        self.assertTrue(github.repo["private"])
        self.assertEqual({endpoint for endpoint, _, _ in github.writes},
                         {BASE, BASE + "/actions/permissions/workflow"})
        self.assertEqual(github.rules.keys(), {10})
        self.assertEqual(github.approval["approval_policy"], "first_time_contributors")

    def test_inspection_reports_drift_without_writing(self):
        github = GitHub()
        self.assertEqual(run(github, apply=False), 1)
        self.assertEqual(github.writes, [])

    def test_other_writers_are_preserved_and_require_deliberate_review(self):
        github = GitHub()
        github.collaborators.append({"login": "someone", "permissions": {"push": True}})
        with self.assertRaisesRegex(RuntimeError, "Review existing write access"):
            run(github)
        self.assertEqual(github.writes, [])
        self.assertEqual(len(github.collaborators), 2)

    def test_non_owner_is_rejected_before_writes(self):
        github = GitHub()
        github.actor = "someone"
        with self.assertRaisesRegex(RuntimeError, "Run as omerholz"):
            run(github)
        self.assertEqual(github.writes, [])

    def test_different_default_branch_is_rejected_before_writes(self):
        github = GitHub()
        github.repo["default_branch"] = "development"
        with self.assertRaisesRegex(RuntimeError, "default"):
            run(github)
        self.assertEqual(github.writes, [])


if __name__ == "__main__":
    unittest.main()
