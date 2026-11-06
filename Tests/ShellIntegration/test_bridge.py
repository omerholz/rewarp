"""Protocol tests runnable without Swift or macOS; the app tests exercise hooks."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest
from urllib.parse import quote_from_bytes

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = os.environ.get("REWARP_SHELL_BRIDGE", str(ROOT / ".build/debug/RewarpShellBridge"))


class BridgeTests(unittest.TestCase):
    def run_bridge(self, *args, data=b""):
        return subprocess.run([BRIDGE, *args], input=data, capture_output=True, check=False)

    def test_every_byte_round_trips_through_encoding(self):
        payload = bytes(range(256))
        result = self.run_bridge("encode", data=payload)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.decode(), quote_from_bytes(payload, safe="/-._~"))

    def test_report_encodes_control_bytes_and_multiline_values(self):
        value = "a\nb\x1b]7701;start=forged;evil\a日本語".encode()
        result = self.run_bridge("report", "cwd", data=b"test-token\n" + value)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"\x1b]7701;cwd=test-token;"
                         + quote_from_bytes(value, safe="/-._~").encode() + b"\a")

    def test_invalid_credentials_or_keys_emit_nothing(self):
        for token in (b"", b"missing-newline", b"\n", b"bad;token\n", b"a" * 129 + b"\n", b"bad\x00token\n"):
            with self.subTest(token=token):
                result = self.run_bridge("report", "cwd", data=token)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
        result = self.run_bridge("report", "cwd;start", data=b"test-token\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_shared_hooks_preserve_exit_status_and_only_resend_changed_names(self):
        for shell in ("bash", "zsh"):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell):
                script = '''
_rewarp_helper=$1
_rewarp_token=test-token
. "$2/resources/shell-integration/common.sh"
_rewarp_command_start 'echo hello'
_rewarp_prompt 42 'first'
_rewarp_command_start 'alias second=true'
_rewarp_prompt 0 'first second'
'''
                result = subprocess.run([shell, "-c", script, "test", BRIDGE, str(ROOT)],
                                        capture_output=True, check=True)
                self.assertIn(b"start=test-token;echo%20hello", result.stdout)
                self.assertIn(b"done=test-token;42", result.stdout)
                self.assertIn(b"names=test-token;first%20second", result.stdout)
                self.assertEqual(result.stdout.count(b"path=test-token;"), 1)
                self.assertLess(result.stdout.index(b"done=test-token;42"),
                                result.stdout.index(b"names=test-token;first"))


if __name__ == "__main__":
    unittest.main()
