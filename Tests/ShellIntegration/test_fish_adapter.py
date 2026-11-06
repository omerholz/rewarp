import os
import shutil
import socket
import unittest

from shell_fixture import REPORT, ROOT, TOKEN, ShellFixture


@unittest.skipUnless(shutil.which("fish"), "fish is required")
class FishAdapterTests(unittest.TestCase):
    def shell(self, startup=None):
        script = ROOT / "resources/shell-integration/fish/bootstrap.fish"
        return ShellFixture(shell=os.environ.get("REWARP_TEST_FISH", "fish"), startup=startup,
                            argv=["-fish", "--no-config", "--interactive", "--init-command",
                                  'source "$REWARP_SHELL_INIT"'],
                            environment={"REWARP_SHELL_INIT": str(script)})

    def test_normal_startup_blocks_status_and_private_bootstrap(self):
        with self.shell({
            ".config/fish/conf.d/example.fish": "set -gx FROM_CONF_D yes\n",
            ".config/fish/config.fish": "set -gx FROM_CONFIG yes\nset -g fish_greeting\n",
        }) as shell:
            shell.ready()
            if hasattr(socket, "SO_PEERCRED"):
                self.assertEqual(shell.helper_parents, [shell.pid])
            output, events = shell.run('printf "STARTUP:%s:%s\\n" "$FROM_CONF_D" "$FROM_CONFIG"')
            self.assertIn(b"STARTUP:yes:yes", output)
            self.assertIn(("done", "0"), events)
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            output, _ = shell.run("echo $status")
            self.assertIn(b"1\r\n", output)
            output, _ = shell.run("status is-login; and echo login")
            self.assertIn(b"login\r\n", output)
            output, _ = shell.run("env | grep -c -E 'REWARP_(SOCKET|SHELL_HELPER|SHELL_INIT)'")
            self.assertIn(b"0\r\n", output)

    def test_user_prompt_keeps_status_and_pipeline_status(self):
        with self.shell({".config/fish/config.fish": '''
function fish_prompt
    printf 'USER_PROMPT:%s:%s> ' $status (string join , -- $pipestatus)
end
function fish_right_prompt
    printf 'RIGHT_PROMPT'
end
'''}) as shell:
            shell.ready()
            output, events = shell.run("false | true")
            self.assertIn(b"USER_PROMPT:0:1,0>", output)
            self.assertIn(b"RIGHT_PROMPT", output)
            self.assertIn(("done", "0"), events)
            output, events = shell.run("false")
            self.assertIn(b"USER_PROMPT:1:1>", output)
            self.assertIn(("done", "1"), events)

    def test_dynamic_functions_abbreviations_and_prompt_replacement(self):
        with self.shell() as shell:
            shell.ready()
            _, events = shell.run("function rewarp_fish_function; echo fish_function; end")
            self.assertTrue(any(key == "names" and "rewarp_fish_function" in value for key, value in events))
            output, _ = shell.run("rewarp_fish_function")
            self.assertIn(b"fish_function\r\n", output)
            _, events = shell.run("abbr --add rewarp_fish_abbr echo abbreviation")
            self.assertTrue(any(key == "names" and "rewarp_fish_abbr" in value for key, value in events))
            shell.run("function fish_prompt; printf 'REPLACED> '; end")
            output, _ = shell.run("echo still_ready")
            self.assertIn(b"REPLACED>", output)

    def test_trace_does_not_print_credential_outside_authenticated_frames(self):
        with self.shell({".config/fish/config.fish": "set -g fish_trace 1\n"}) as shell:
            shell.ready()
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            self.assertNotIn(TOKEN.encode(), REPORT.sub(b"", shell.output))


if __name__ == "__main__":
    unittest.main()
