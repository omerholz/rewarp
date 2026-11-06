"""End-to-end checks of the input editor. IDs refer to docs/warp-parity.md."""
import os

from harness import App

HISTORY = ": 1:0;git status\n: 2:0;git stash\n: 3:0;ls -la\n: 4:0;docker ps\n"


def with_history(test):
    def wrapper():
        with App(history=HISTORY) as app:
            app.ready()
            test(app)
    wrapper.__name__ = test.__name__
    return wrapper


@with_history
def test_aut_001_ghost_text_suggests_from_history(app):
    assert app.type("git st")["ghost"] == "ash"


@with_history
def test_aut_003_right_arrow_accepts_ghost_text(app):
    app.type("git st")
    state = app.key("right")
    assert state["input"] == "git stash"
    assert state["ghost"] is None


@with_history
def test_inp_083_escape_clears_ghost_text(app):
    app.type("git st")
    assert app.key("escape")["ghost"] is None


@with_history
def test_inp_087_enter_ignores_ghost_text(app):
    app.type("echo gh")
    state = app.key("return")
    assert app.wait("the block", lambda s: s["blocks"] and s["blocks"][0]["command"] == "echo gh")


@with_history
def test_his_004_up_opens_history_menu(app):
    state = app.key("up")
    assert state["menuOpen"]
    assert state["menuMode"] == "history"
    assert state["menuItems"][0] == "docker ps"


@with_history
def test_his_005_history_menu_filters_by_prefix(app):
    app.type("git")
    assert app.key("up")["menuItems"] == ["git stash", "git status"]


@with_history
def test_his_008_arrows_move_one_item_at_a_time(app):
    app.key("up")
    assert app.key("up")["menuSelected"] == 1
    assert app.key("up")["menuSelected"] == 2
    assert app.key("down")["menuSelected"] == 1


@with_history
def test_his_011_escape_closes_the_menu_and_restores_input(app):
    app.type("git")
    app.key("up")
    state = app.key("escape")
    assert not state["menuOpen"]
    assert state["input"] == "git"


@with_history
def test_his_009_cmd_enter_runs_the_highlighted_item(app):
    app.key("up")
    app.key("return", "cmd")
    state = app.wait("the block", lambda s: s["blocks"])
    assert state["blocks"][0]["command"] == "docker ps"


def test_inp_004_enter_submits(app):
    app.type("echo sent")
    app.key("return")
    state = app.wait("the output", lambda s: s["blocks"] and not s["blocks"][0]["running"])
    assert state["blocks"][0]["output"] == "sent"
    assert state["input"] == ""


def test_inp_055_ctrl_j_inserts_a_newline_and_shift_enter_too(app):
    app.type("echo a")
    app.key("j", "ctrl")
    state = app.type("echo b")
    assert state["input"] == "echo a\necho b"
    state = app.key("return", "shift")
    assert state["input"] == "echo a\necho b\n"


def test_inp_005_input_grows_with_content(app):
    before = app.state()["inputHeight"]
    app.type("a")
    app.key("j", "ctrl")
    assert app.type("b")["inputHeight"] > before


def test_inp_003_typing_replaces_a_selection(app):
    app.type("hello")
    app.key("a", "cmd")
    assert app.type("x")["input"] == "x"


def test_cmp_001_tab_opens_completions(app):
    app.type("git ")
    state = app.key("tab")
    assert state["menuMode"] == "completions"
    assert "checkout" in state["menuItems"]


def test_cmp_007_nothing_is_selected_when_the_menu_opens(app):
    app.type("git ")
    assert app.key("tab")["menuSelected"] is None


def test_cmp_007_enter_with_nothing_selected_runs_the_input(app):
    app.type("git ")
    app.key("tab")
    app.key("return")
    state = app.wait("the block", lambda s: s["blocks"])
    assert state["blocks"][0]["command"].strip() == "git"


def test_cmp_005_arrows_pick_an_item_and_write_it_into_the_input(app):
    app.type("git ")
    app.key("tab")
    state = app.key("down")
    assert state["menuSelected"] == 0
    assert state["input"] == "git " + state["menuItems"][0]


def test_cmp_011_accepting_a_completion_appends_a_space(app):
    app.type("git chec")
    state = app.key("tab")
    assert state["input"] == "git checkout "
    assert not state["menuOpen"]


def test_cmp_009_common_prefix_fills_in(app):
    for name in ["report-a.txt", "report-b.txt"]:
        open(os.path.join(app.home, name), "w").close()
    app.type("cat rep")
    state = app.key("tab")
    assert state["input"] == "cat report-"
    assert len(state["menuItems"]) == 2


def test_cmp_012_directories_stay_open(app):
    os.mkdir(os.path.join(app.home, "projects"))
    app.type("cd proj")
    assert app.key("tab")["input"] == "cd projects/"


def test_cmp_015_escape_closes_the_menu(app):
    app.type("git ")
    app.key("tab")
    assert not app.key("escape")["menuOpen"]


def test_cmp_016_typing_refilters(app):
    app.type("git ")
    app.key("tab")
    state = app.type("che")
    assert state["menuItems"][0] == "checkout"


def test_cmp_022_completion_works_mid_line(app):
    app.type("git chec main")
    for _ in range(5):
        app.key("left")
    assert app.key("tab")["input"] == "git checkout  main"


def test_cmp_023_completion_after_and(app):
    app.type("true && git chec")
    assert app.key("tab")["input"] == "true && git checkout "


def test_cmp_035_paths_are_the_fallback(app):
    open(os.path.join(app.home, "notes.txt"), "w").close()
    app.type("unknown-tool not")
    assert app.key("tab")["input"] == "unknown-tool notes.txt "


def test_cmp_038_aliases_complete():
    with App(zshrc="alias rwtest='echo alias'\n") as app:
        app.ready()
        app.run("true")
        app.type("rwtes")
        assert app.key("tab")["input"] == "rwtest "


@with_history
def test_cmp_021_ctrl_r_replaces_the_completions_menu(app):
    app.type("git ")
    app.key("tab")
    assert app.key("r", "ctrl")["menuMode"] == "search"


@with_history
def test_csr_001_ctrl_r_opens_search(app):
    state = app.key("r", "ctrl")
    assert state["menuMode"] == "search"
    assert state["menuItems"][0] == "docker ps"


@with_history
def test_csr_005_search_is_fuzzy(app):
    app.key("r", "ctrl")
    assert app.type("gst")["menuItems"][0] in ("git status", "git stash")


@with_history
def test_csr_002_enter_puts_the_result_in_the_input(app):
    app.key("r", "ctrl")
    app.type("docker")
    state = app.key("return")
    assert state["input"] == "docker ps"
    assert state["blocks"] == []
    assert not state["menuOpen"]


@with_history
def test_csr_003_cmd_enter_runs_it(app):
    app.key("r", "ctrl")
    app.type("docker")
    app.key("return", "cmd")
    state = app.wait("the block", lambda s: s["blocks"])
    assert state["blocks"][0]["command"] == "docker ps"


@with_history
def test_csr_010_ctrl_c_closes_search(app):
    app.key("r", "ctrl")
    app.type("docker")
    state = app.key("c", "ctrl")
    assert not state["menuOpen"]
    assert state["input"] == ""


def test_cor_017_cmd_l_focuses_the_input(app):
    app.run("echo one")
    app.key("up", "cmd")
    assert app.key("l", "cmd")["focus"] == "input"


def test_hostile_branch_name_cannot_run_a_command(app):
    refs = os.path.join(app.home, ".git", "refs", "heads")
    os.makedirs(refs)
    open(os.path.join(app.home, ".git", "HEAD"), "w").write("ref: refs/heads/main\n")
    marker = os.path.join(app.home, "pwned")
    open(os.path.join(refs, "$(touch pwned)"), "w").close()

    app.type("git checkout ")
    state = app.key("tab")
    assert "\\$\\(touch\\ pwned\\)" in state["input"], state["input"]
    app.key("return")
    app.wait("the command to finish", lambda s: s["blocks"] and not s["blocks"][-1]["running"])
    assert not os.path.exists(marker)
