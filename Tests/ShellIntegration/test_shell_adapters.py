import os
from pathlib import Path
import shlex
import shutil
import unittest

from shell_fixture import REPORT, ROOT, TOKEN, ShellFixture


@unittest.skipUnless(shutil.which("zsh"), "zsh is required")
class ZshAdapterTests(unittest.TestCase):
    def test_xtrace_does_not_print_the_integration_credential(self):
        with ShellFixture(startup={".zshenv": "set -x\n", ".zshrc": "PROMPT='trace> '\n"}) as shell:
            shell.ready()
            shell.run("echo trace_works")
            self.assertNotIn(TOKEN.encode(), REPORT.sub(b"", shell.output))

    def test_normal_login_files_status_and_alias_updates(self):
        with ShellFixture(startup={
            ".zshenv": "export TEST_ENV=env\n",
            ".zprofile": "export TEST_PROFILE=profile\n",
            ".zshrc": "export TEST_RC=rc\nPROMPT='test> '\n",
            ".zlogin": "export TEST_LOGIN=login\n",
        }) as shell:
            shell.ready()
            output, _ = shell.run('printf "RESULT:%s:%s:%s:%s\\n" "$TEST_ENV" "$TEST_PROFILE" "$TEST_RC" "$TEST_LOGIN"')
            self.assertIn(b"RESULT:env:profile:rc:login", output)
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)
            _, events = shell.run("alias rewarp_added_alias='echo alias_works'")
            self.assertTrue(any(key == "names" and "rewarp_added_alias" in value for key, value in events))
            output, _ = shell.run("env | grep -c REWARP")
            self.assertIn(b"0\r\n", output)

    def test_actual_oh_my_zsh_and_reload(self):
        framework = Path(os.environ.get("REWARP_TEST_OMZ", str(ROOT / "vendor/test-oh-my-zsh")))
        self.assertTrue((framework / "oh-my-zsh.sh").is_file(), "run scripts/fetch-shell-fixtures.sh")
        config = f'''
export ZSH={shlex.quote(str(framework))}
ZSH_THEME=robbyrussell
plugins=(git)
ZSH_CACHE_DIR="$HOME/omz-cache"
zstyle ':omz:update' mode disabled
source "$ZSH/oh-my-zsh.sh"
'''
        with ShellFixture(startup={".zshrc": config}) as shell:
            shell.ready()
            output, _ = shell.run("type gst >/dev/null && echo OMZ_LOADED")
            self.assertIn(b"OMZ_LOADED\r\n", output)
            before = len(shell.events)
            os.write(shell.fd, b"omz reload\n")
            shell.wait(lambda events: any(key == "hello" for key, _ in events[before:])
                       and any(key == "ready" for key, _ in events[before:]), timeout=20)
            output, _ = shell.run("echo RELOADED")
            self.assertIn(b"RELOADED\r\n", output)
            _, events = shell.run("false")
            self.assertIn(("done", "1"), events)


if __name__ == "__main__":
    unittest.main()
