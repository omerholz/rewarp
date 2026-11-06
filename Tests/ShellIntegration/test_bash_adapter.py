import os
import shutil
import socket
import subprocess
import unittest

from shell_fixture import REPORT, ROOT, TOKEN, ShellFixture


@unittest.skipUnless(shutil.which("bash"), "bash is required")
class BashAdapterTests(unittest.TestCase):
    def shell(self, startup=None):
        script = ROOT / "resources/shell-integration/bash/bootstrap.bash"
        return ShellFixture(shell=os.environ.get("REWARP_TEST_BASH", "bash"), argv=["-bash", "--noprofile", "-i"],
                            startup=startup, environment={"REWARP_SHELL_INIT": str(script),
                                                          "HISTCONTROL": "ignorespace", "HISTFILE": ""},
                            initial_input=' builtin source -- "$REWARP_SHELL_INIT"\n')

    def test_login_files_blocks_status_and_private_history(self):
        with self.shell({".bash_profile": 'export PROFILE_LOADED=yes\nsource "$HOME/.bashrc"\n',
                         ".bashrc": "HISTCONTROL=ignorespace\nPS1='custom> '\n"}) as shell:
            shell.ready()
            if hasattr(socket, "SO_PEERCRED"):
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
            output, _ = shell.run("shopt -q login_shell && echo login")
            self.assertIn(b"login\r\n", output)

    def test_existing_debug_trap_and_xtrace_keep_working_without_disclosing_token(self):
        with self.shell({".bash_profile": "trap 'if [[ $BASH_COMMAND == *REWARP_DEBUG_SENTINEL* ]]; then DEBUG_SEEN=observed; fi' DEBUG\nset -x\n"}) as shell:
            shell.ready()
            output, _ = shell.run(': REWARP_DEBUG_SENTINEL; printf "DEBUG:%s\\n" "$DEBUG_SEEN"')
            self.assertIn(b"DEBUG:observed", output)
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            self.assertNotIn(TOKEN.encode(), REPORT.sub(b"", shell.output))

    def test_profile_selected_history_file_and_prompt_status(self):
        with self.shell({".bash_profile": 'HISTFILE="$HOME/custom_history"\nPS1=\'STATUS:$? > \'\n',
                         "custom_history": "echo PREVIOUS_SESSION\n",
                         ".bash_history": "echo UNSELECTED_HISTORY\n"}) as shell:
            shell.ready()
            output, _ = shell.run("history")
            self.assertIn(b"echo PREVIOUS_SESSION", output)
            self.assertNotIn(b"UNSELECTED_HISTORY", output)
            self.assertNotIn(b"builtin source", output)
            output, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            self.assertIn(b"STATUS:1 >", output)

    def test_prompt_hooks_receive_original_status_and_pipeline_status(self):
        version = tuple(map(int, subprocess.check_output([
            os.environ.get("REWARP_TEST_BASH", "bash"), "-c",
            'printf "%s %s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
        ]).split()))
        config = '''
PROMPT_COMMAND='USER_STATUS=$? USER_PIPE=("${PIPESTATUS[@]}")'
PS1='STATUS:$USER_STATUS PIPE:${USER_PIPE[*]}> '
'''
        with self.shell({".bash_profile": config}) as shell:
            shell.ready()
            output, _ = shell.run("false | true")
            self.assertIn(b"STATUS:0 ", output)
            if version >= (4, 4):
                self.assertIn(b"STATUS:0 PIPE:1 0>", output)
            output, _ = shell.run("false")
            self.assertIn(b"STATUS:1 ", output)
            if version >= (4, 4):
                self.assertIn(b"STATUS:1 PIPE:1>", output)
            _, events = shell.run("echo )")
            self.assertFalse(any(key == "start" for key, _ in events))

    def test_array_or_scalar_prompt_commands_preserve_each_user_action(self):
        config = '''
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
    PROMPT_COMMAND=('USER_PC_ONE=one' 'USER_PC_TWO=two')
else
    PROMPT_COMMAND='USER_PC_ONE=one; USER_PC_TWO=two'
fi
'''
        with self.shell({".bash_profile": config}) as shell:
            shell.ready()
            output, events = shell.run('printf "HOOKS:%s:%s\\n" "$USER_PC_ONE" "$USER_PC_TWO"')
            self.assertIn(b"HOOKS:one:two", output)
            self.assertIn(("done", "0"), events)

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
