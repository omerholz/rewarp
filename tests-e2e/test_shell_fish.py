"""Full Fish command editor, blocks, startup files, and completion routing."""
import os
import shutil

from harness import App

FISH = os.environ.get("REWARP_TEST_FISH", shutil.which("fish"))


def test_shell_fish_completes_percent_filename_literally():
    assert FISH, "install Fish before running its integration tests"
    with App(shell=FISH, startup_files={"%self": "literal_percent_file\n"}) as app:
        app.type("cat %se")
        assert app.key("tab")["input"] == r"cat \%self "
        app.key("return")
        state = app.wait("literal percent filename", lambda s: s["phase"] == "ready" and s["blocks"]
                         and not s["blocks"][-1]["running"])
        assert state["blocks"][-1]["output"] == "literal_percent_file"


def test_shell_fish_startup_blocks_status_and_completions():
    assert FISH, "install Fish before running its integration tests"
    startup = {
        ".config/fish/fish_variables": "# VERSION: 3.0\nSETUVAR rewarp_fixture_universal:original\n",
        ".config/fish/conf.d/example.fish": "set -gx FROM_CONF_D yes\n",
        ".config/fish/config.fish": "set -gx FROM_CONFIG yes\nfunction rewarp_fish_function; echo fish_function; end\n",
    }
    with App(shell=FISH, startup_files=startup) as app:
        state = app.run('echo "$FROM_CONF_D:$FROM_CONFIG"')
        assert state["blocks"][-1]["output"] == "yes:yes"
        assert app.run("echo $rewarp_fixture_universal")["blocks"][-1]["output"] == "original"
        app.run("set -U rewarp_fixture_universal updated")
        assert app.run("fish -c 'echo $rewarp_fixture_universal'")["blocks"][-1]["output"] == "updated"
        command = "printf 'pipeline_output\\n' | cat"
        state = app.run(command)
        assert state["blocks"][-1]["command"] == command
        assert state["blocks"][-1]["output"] == "pipeline_output"
        assert app.run("false")["blocks"][-1]["exit"] == 1
        assert app.run("echo $status")["blocks"][-1]["output"] == "1"
        app.type("rewarp_fish_fun")
        assert app.key("tab")["input"] == "rewarp_fish_function "
        app.key("return")
        app.wait("Fish function", lambda s: s["blocks"][-1]["output"] == "fish_function")
        app.run("mkdir subdirectory; cd subdirectory")
        directory = app.run("pwd")["blocks"][-1]["output"]
        # Fish may canonicalize macOS's /var -> /private/var alias. Compare the
        # actual directory, preserving validation of cd without imposing spelling.
        assert os.path.samefile(directory, os.path.join(app.home, "subdirectory")), repr(directory)


def test_shell_fish_prompt_changes_and_private_bootstrap():
    assert FISH, "install Fish before running its integration tests"
    with App(shell=FISH, startup_files={
        ".config/fish/config.fish": "function fish_prompt; printf 'CUSTOM_PROMPT> '; end\n",
    }) as app:
        app.run("function fish_prompt; printf 'REPLACED> '; end")
        assert app.run("echo after")["blocks"][-1]["output"] == "after"
        state = app.run('if "$_rewarp_helper" token "$_rewarp_socket"; echo LEAKED; else; echo DENIED; end')
        assert state["blocks"][-1]["output"] == "DENIED"
        state = app.run("env | grep -c -E 'REWARP_(SOCKET|SHELL_HELPER|SHELL_INIT)'")
        assert state["blocks"][-1]["output"] == "0"


def test_shell_fish_interactive_input_and_interrupt_return_to_editor():
    assert FISH, "install Fish before running its integration tests"
    with App(shell=FISH) as app:
        app.type("cat")
        app.key("return")
        app.wait("Fish running cat", lambda s: s["inputHidden"] and s["focus"] == "terminal")
        app.type("interactive_input")
        app.key("return")
        app.wait("cat output", lambda s: "interactive_input" in s["blocks"][-1]["output"])
        app.key("c", "ctrl")
        state = app.wait("Fish prompt", lambda s: s["phase"] == "ready")
        assert state["blocks"][-1]["exit"] == 130
        assert app.run("echo after_interrupt")["blocks"][-1]["output"] == "after_interrupt"
