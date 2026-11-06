"""Exercise source publication helpers against isolated real Git repositories."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SourceToolsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rewarp-source-test-")
        self.addCleanup(self.temporary.cleanup)
        self.scratch = Path(self.temporary.name)
        self.repo = self.scratch / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        for script in ("prepare-public.sh", "scan-secrets.sh"):
            shutil.copy2(ROOT / "scripts" / script, self.repo / "scripts" / script)
        self.env = dict(os.environ)
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
                    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG_COUNT"):
            self.env.pop(key, None)
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
        self.git("init", "-q", "-b", "main")
        (self.repo / ".gitignore").write_text("ignored.env\n")
        (self.repo / "tracked").mkdir()
        (self.repo / "tracked" / "note.txt").write_text("public source\n")
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "Private original history")
        self.original = self.git("rev-parse", "HEAD").stdout.strip()
        (self.repo / "ignored.env").write_text("IGNORED_COPY_CANARY\n")

    def git(self, *args, cwd=None, check=True):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env,
                              capture_output=True, text=True, check=check)

    def export(self, destination, check=True):
        return subprocess.run(["bash", "scripts/prepare-public.sh", str(destination)],
                              cwd=self.repo, env=self.env, capture_output=True,
                              text=True, check=check)

    def replace_parent_with_external_symlink(self):
        external = self.scratch / "external"
        external.mkdir()
        (external / "note.txt").write_text("OUTSIDE_COPY_CANARY\n")
        shutil.rmtree(self.repo / "tracked")
        (self.repo / "tracked").symlink_to(external, target_is_directory=True)

    def test_export_has_one_noreply_root_commit_and_excludes_ignored_files(self):
        destination = self.scratch / "public"
        self.export(destination)
        self.assertEqual(self.git("rev-list", "--count", "--all", cwd=destination).stdout.strip(), "1")
        self.assertEqual(len(self.git("rev-list", "--parents", "HEAD", cwd=destination).stdout.split()), 1)
        self.assertEqual(self.git("log", "-1", "--format=%ae%n%ce", cwd=destination).stdout.splitlines(),
                         ["2319152+omerholz@users.noreply.github.com"] * 2)
        self.assertFalse(self.git("remote", cwd=destination).stdout.strip())
        self.assertNotEqual(self.git("cat-file", "-e", self.original, cwd=destination, check=False).returncode, 0)
        self.assertFalse((destination / "ignored.env").exists())

    def test_export_refuses_existing_and_nested_destinations(self):
        existing = self.scratch / "existing"
        existing.mkdir()
        sentinel = existing / "sentinel"
        sentinel.write_text("keep me")
        self.assertNotEqual(self.export(existing, check=False).returncode, 0)
        self.assertEqual(sentinel.read_text(), "keep me")
        nested = self.repo / "public"
        self.assertNotEqual(self.export(nested, check=False).returncode, 0)
        self.assertFalse(nested.exists())

    def test_export_and_scan_do_not_dereference_symlinked_parents(self):
        self.replace_parent_with_external_symlink()
        destination = self.scratch / "public"
        self.export(destination)
        self.assertNotEqual(self.git("cat-file", "-e", "HEAD:tracked/note.txt",
                                     cwd=destination, check=False).returncode, 0)
        # The fake scanner fails if ignored or external data reached its staging
        # directory. Git history itself is covered by the real CI secret scan.
        binary = self.scratch / "bin"
        binary.mkdir()
        scanner = binary / "gitleaks"
        scanner.write_text('''#!/usr/bin/env python3
from pathlib import Path
import sys
if sys.argv[1] == "dir":
    root = Path(sys.argv[2])
    for path in root.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            if b"OUTSIDE_COPY_CANARY" in data or b"IGNORED_COPY_CANARY" in data:
                sys.exit(9)
''')
        scanner.chmod(0o755)
        result = subprocess.run(["bash", "scripts/scan-secrets.sh"], cwd=self.repo,
                                env=dict(self.env, PATH=str(binary) + os.pathsep + self.env["PATH"]),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
