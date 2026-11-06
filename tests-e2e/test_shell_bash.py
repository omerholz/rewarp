"""Full Bash editor/block integration using the macOS system Bash."""
import os

from harness import App


def test_shell_bash_login_blocks_status_and_completions():
    startup = {
        ".bash_profile": 'export BASH_PROFILE_LOADED=yes\nsource "$HOME/.bashrc"\n',
        ".bashrc": "HISTCONTROL=ignorespace\nalias rewarp_bash_alias='echo alias_works'\n",
    }
    with App(shell="/bin/bash", startup_files=startup) as app:
        state = app.run('echo "$BASH_PROFILE_LOADED"')
        assert state["blocks"][-1]["output"] == "yes"
        command = "printf 'pipeline_output\\n' | cat"
        state = app.run(command)
        assert state["blocks"][-1]["command"] == command
        assert state["blocks"][-1]["output"] == "pipeline_output"
        assert app.run("false")["blocks"][-1]["exit"] == 1
        assert app.run("echo $?")["blocks"][-1]["output"] == "1"
        app.type("rewarp_bash_al")
        assert app.key("tab")["input"] == "rewarp_bash_alias "
        app.key("return")
        app.wait("Bash alias", lambda s: s["blocks"][-1]["output"] == "alias_works")
        assert app.run('echo "$HISTCONTROL"')["blocks"][-1]["output"] == "ignorespace"


def test_shell_bash_preserves_prompt_hooks_and_denies_later_token_requests():
    with App(shell="/bin/bash", startup_files={
        ".bash_profile": "PROMPT_COMMAND='PS1=\"user_prompt> \"'\ntrap 'DEBUG_SEEN=1' DEBUG\n",
    }) as app:
        state = app.run('printf "%s:%s" "$DEBUG_SEEN" "$PS1"')
        assert state["blocks"][-1]["output"].startswith("1:user_prompt> ")
        state = app.run('if "$_rewarp_helper" token "$_rewarp_socket"; then echo LEAKED; else echo DENIED; fi')
        assert state["blocks"][-1]["output"] == "DENIED"
        app.run("mkdir subdirectory; cd subdirectory")
        assert app.run("pwd")["blocks"][-1]["output"] == os.path.join(app.home, "subdirectory")
