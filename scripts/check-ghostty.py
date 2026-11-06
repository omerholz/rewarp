#!/usr/bin/env python3
"""Check the pinned Ghostty commit against upstream changes and advisories."""
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
API = "https://api.github.com/repos/ghostty-org/ghostty"


def fetch(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "rewarp-dependency-monitor",
               "X-GitHub-Api-Version": "2022-11-28"}
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]
    request = urllib.request.Request(API + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    version = (ROOT / "scripts/ghostty-version.env").read_text()
    match = re.search(r"^GHOSTTY_COMMIT=([a-f0-9]{40})$", version, re.MULTILINE)
    if not match:
        raise ValueError("expected a full Ghostty commit pin")
    pin = match.group(1)
    repository = fetch("")
    comparison = fetch(f"/compare/{pin}...{repository['default_branch']}")
    advisories = []
    page = 1
    while True:
        batch = fetch(f"/security-advisories?per_page=100&page={page}")
        advisories.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    reviews = json.loads((ROOT / "security/ghostty-advisory-reviews.json").read_text())["reviews"]
    # A review expires when the pin or the upstream advisory changes. A review
    # must carry a rationale; listing an ID alone cannot suppress an alert.
    reviewed = {(item["ghsa_id"], item["commit"], item["updated_at"])
                for item in reviews if item.get("rationale", "").strip()}
    unresolved = [item for item in advisories
                  if (item["ghsa_id"], pin, item["updated_at"]) not in reviewed]
    lines = ["# Ghostty dependency review", "", f"Pinned commit: `{pin}`",
             f"Upstream comparison: {comparison['html_url']}",
             f"Upstream commits ahead: {comparison['ahead_by']}",
             f"Published advisories: {len(advisories)}; requiring review: {len(unresolved)}", ""]
    for item in unresolved:
        # Do not insert upstream-controlled titles into workflow commands.
        lines.append(f"- {item['ghsa_id']}: {item['html_url']}")
    report = "\n".join(lines) + "\n"
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write(report)
    if comparison["ahead_by"]:
        print("::warning::Ghostty has upstream changes; review the dependency report.")
    if comparison["status"] == "diverged":
        print("::error::The Ghostty pin diverges from upstream; investigate its provenance.")
        return 1
    if unresolved:
        print("::error::Published Ghostty advisories require review against the pinned commit.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
