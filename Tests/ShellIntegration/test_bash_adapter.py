import shutil
import unittest

from shell_fixture import ROOT, ShellFixture


@unittest.skipUnless(shutil.which("bash"), "bash is required")
class BashAdapterTests(unittest.TestCase):
    def shell(self, startup=None):
        script = ROOT / "resources/shell-integration/bash/bootstrap.bash"
        return ShellFixture(shell="bash", argv=["-bash", "--noprofile", "--posix", "-i"],
                            startup=startup, environment={"ENV": str(script), "REWARP_SHELL_INIT": str(script)})

    def test_login_files_blocks_status_and_private_history(self):
        with self.shell({".bash_profile": 'export PROFILE_LOADED=yes\nsource "$HOME/.bashrc"\n',
                         ".bashrc": "HISTCONTROL=ignorespace\nPS1='custom> '\n"}) as shell:
            shell.ready()
            if shell.helper_parents:
                self.assertEqual(shell.helper_parents, [shell.pid])
            output, events = shell.run('printf "PROFILE:%s\\n" "$PROFILE_LOADED"')
            self.assertIn(b"PROFILE:yes", output)
            self.assertIn(("done", "0"), events)
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            output, _ = shell.run("echo $?")
            self.assertIn(b"1\r\n", output)
            _, events = shell.run(" echo PRIVATE_HISTORY_SENTINEL")
            self.assertTrue(any(key == "start" for key, _ in events))
            output, _ = shell.run("history")
            self.assertNotIn(b" echo PRIVATE_HISTORY_SENTINEL", output)
            output, _ = shell.run('printf "HIST:%s\\n" "$HISTCONTROL"')
            self.assertIn(b"HIST:ignorespace", output)

    def test_prompt_command_and_alias_changes_are_preserved(self):
        with self.shell({".bash_profile": 'PROMPT_COMMAND=\'PS1="changed> "\'\n'}) as shell:
            shell.ready()
            output, _ = shell.run('printf "PROMPT:%s\\n" "$PS1"')
            self.assertIn(b"PROMPT:changed>", output)
            _, events = shell.run("alias rewarp_bash_alias='echo alias_works'")
            self.assertTrue(any(key == "names" and "rewarp_bash_alias" in value for key, value in events))
            output, _ = shell.run("rewarp_bash_alias")
            self.assertIn(b"alias_works\r\n", output)
            output, _ = shell.run("env | grep -c -E 'REWARP_(SOCKET|SHELL_HELPER|SHELL_INIT)'")
            self.assertIn(b"0\r\n", output)


if __name__ == "__main__":
    unittest.main()
