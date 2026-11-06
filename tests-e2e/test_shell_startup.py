"""Startup and real prompt-framework compatibility, isolated from user dotfiles."""
import os
from pathlib import Path
import shlex

from harness import App, ROOT


def test_shell_zsh_preserves_login_startup_and_user_prompt():
    with App(zshrc="export FROM_RC=yes\nPROMPT='custom> '\n", startup_files={
        ".zshenv": "export FROM_ENV=yes\n",
        ".zprofile": "export FROM_PROFILE=yes\n",
        ".zlogin": "export FROM_LOGIN=yes\n",
    }) as app:
        state = app.run('echo "$FROM_ENV:$FROM_PROFILE:$FROM_RC:$FROM_LOGIN"')
        assert state["blocks"][-1]["output"] == "yes:yes:yes:yes"
        assert app.run("false")["blocks"][-1]["exit"] == 1
        assert app.run("[[ -o login ]] && echo login")["blocks"][-1]["output"] == "login"


def test_shell_zsh_honors_zdotdir_set_in_zshenv():
    with App(startup_files={
        ".zshenv": 'export ZDOTDIR="$HOME/config/zsh"\n',
        "config/zsh/.zshrc": "export FROM_CUSTOM_CONFIG=yes\n",
    }) as app:
        state = app.run('echo "$FROM_CUSTOM_CONFIG"')
        assert state["blocks"][-1]["output"] == "yes"
        assert app.run("echo after")["blocks"][-1]["output"] == "after"


def test_shell_zsh_reports_aliases_created_after_startup():
    with App() as app:
        app.run("alias rewarp_added_alias='echo alias_works'")
        state = app.type("rewarp_added_al")
        app.key("tab")
        app.key("return")
        state = app.wait("new alias", lambda s: s["blocks"] and not s["blocks"][-1]["running"]
                         and s["blocks"][-1]["output"] == "alias_works")
        assert state["blocks"][-1]["exit"] == 0


def test_shell_actual_oh_my_zsh_git_plugin_and_reload():
    fixture = Path(os.environ.get("REWARP_TEST_OMZ", str(Path(ROOT) / "vendor/test-oh-my-zsh")))
    assert (fixture / "oh-my-zsh.sh").is_file(), "run scripts/fetch-shell-fixtures.sh first"
    startup = f'''
export ZSH={shlex.quote(str(fixture))}
ZSH_THEME=robbyrussell
plugins=(git)
ZSH_CACHE_DIR="$HOME/omz-cache"
zstyle ':omz:update' mode disabled
source "$ZSH/oh-my-zsh.sh"
'''
    with App(zshrc=startup) as app:
        state = app.run("type gst >/dev/null && echo oh_my_zsh_loaded")
        assert state["blocks"][-1]["output"] == "oh_my_zsh_loaded"
        assert app.run("false")["blocks"][-1]["exit"] == 1
        app.type("omz reload")
        app.key("return")
        app.wait("Oh My Zsh reload", lambda s: s["phase"] == "ready" and s["blocks"]
                 and not s["blocks"][-1]["running"], timeout=20)
        state = app.run("echo reloaded")
        assert state["blocks"][-1]["output"] == "reloaded"
        assert app.run("env | grep -c -E 'REWARP_(SOCKET|SHELL_HELPER)' ")["blocks"][-1]["output"] == "0"
