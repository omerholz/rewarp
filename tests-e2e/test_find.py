"""End-to-end checks of find, filter and palettes. IDs refer to docs/warp-parity.md."""


def test_blk_104_cmd_f_opens_find(app):
    app.run("echo needle")
    state = app.key("f", "cmd")
    assert state["findOpen"]


def test_blk_105_find_searches_all_blocks(app):
    app.run("echo needle one")
    app.run("echo other")
    app.run("echo needle two")
    app.key("f", "cmd")
    state = app.bar_type("needle")
    assert state["findHits"] == 2
    assert state["findLabel"] == "1/2"


def test_blk_110_no_matches_shows_zero(app):
    app.run("echo something")
    app.key("f", "cmd")
    assert app.bar_type("zzzz")["findLabel"] == "0/0"


def test_blk_113_cmd_g_moves_between_matches(app):
    app.run("echo aa")
    app.run("echo aa")
    app.key("f", "cmd")
    app.bar_type("aa")
    assert app.key("g", "cmd")["findLabel"] == "2/2"
    assert app.key("g", "cmd", "shift")["findLabel"] == "1/2"


def test_blk_106_find_limits_to_a_selected_block(app):
    app.run("echo needle")
    app.run("echo needle")
    app.key("up", "cmd")
    app.key("f", "cmd")
    assert app.bar_type("needle")["findHits"] == 1


def test_blk_108_input_stays_usable_while_find_is_open(app):
    app.run("echo needle")
    app.key("f", "cmd")
    app.key("l", "cmd")
    state = app.type("still typing")
    assert state["input"] == "still typing"
    assert state["findOpen"]


def test_blk_121_escape_closes_find(app):
    app.run("echo needle")
    app.key("f", "cmd")
    state = app.key("escape")
    assert not state["findOpen"]


def test_cor_021_finishing_command_does_not_take_focus_from_find(app):
    app.type("sleep 0.4")
    app.key("return")
    app.wait("the block", lambda s: s["blocks"])
    state = app.key("f", "cmd")
    assert state["findOpen"]
    state = app.wait("sleep to finish", lambda s: s["phase"] == "ready")
    app.wait("the event to land", lambda s: True)
    assert app.state()["focus"] == "other"


def test_blk_091_filter_shows_only_matching_rows(app):
    app.run("printf 'alpha\\nbeta\\ngamma\\n'")
    app.key("f", "opt", "shift")
    state = app.bar_type("beta")
    assert state["displayRows"] == ["beta"]
    assert "alpha" in state["blocks"][0]["output"]


def test_blk_096_toggling_with_no_filter_opens_the_editor(app):
    app.run("echo one")
    assert app.key("f", "opt", "shift")["filterOpen"]


def test_blk_098_clearing_restores_all_rows(app):
    app.run("printf 'alpha\\nbeta\\n'")
    app.key("f", "opt", "shift")
    app.bar_type("beta")
    state = app.key("f", "opt", "shift")
    assert state["displayRows"] == ["alpha", "beta"]
    assert not state["filterOpen"]


def test_blk_100_results_update_as_you_type(app):
    app.run("printf 'ab\\nac\\nbc\\n'")
    app.key("f", "opt", "shift")
    assert app.bar_type("a")["displayRows"] == ["ab", "ac"]
    assert app.bar_type("b")["displayRows"] == ["ab"]


def test_blk_101_filter_works_on_a_running_command(app):
    app.type("(echo keep; sleep 0.5; echo drop; sleep 0.5; echo keep2; sleep 1)")
    app.key("return")
    app.wait("the first line", lambda s: s["blocks"] and "keep" in s["blocks"][0]["output"])
    app.key("f", "opt", "shift")
    app.bar_type("keep")
    state = app.wait("the later match", lambda s: s["displayRows"] == ["keep", "keep2"])
    assert "drop" in state["blocks"][0]["output"]


def test_pal_001_cmd_p_opens_and_closes(app):
    state = app.key("p", "cmd")
    assert state["paletteOpen"]
    assert not app.key("p", "cmd")["paletteOpen"]


def test_pal_004_palette_search_is_fuzzy(app):
    app.key("p", "cmd")
    state = app.palette_type("splt rgt")
    assert state["paletteItems"][0] == "Split Pane Right"


def test_pal_006_reopening_resets(app):
    app.key("p", "cmd")
    app.palette_type("split")
    app.key("p", "cmd")
    state = app.key("p", "cmd")
    assert "New Tab" in state["paletteItems"]


def test_pal_011_escape_closes(app):
    app.key("p", "cmd")
    assert not app.key("escape")["paletteOpen"]


def test_pal_003_enter_runs_the_action(app):
    app.key("p", "cmd")
    app.palette_type("split pane right")
    state = app.key("return")
    assert not state["paletteOpen"]
    assert app.wait("the split", lambda s: s["panes"] == 2)


def test_nav_001_navigation_palette(app):
    state = app.key("p", "cmd", "shift")
    assert state["paletteName"] == "sessions"
    assert len(state["paletteItems"]) == 1


def test_nav_002_lists_every_session(app):
    app.key("t", "cmd")
    app.wait("the second tab", lambda s: s["tabs"] == 2)
    assert len(app.key("p", "cmd", "shift")["paletteItems"]) == 2


def test_text_selection_works_on_filtered_output(app):
    app.run("printf 'alpha\\nbeta\\ngamma\\n'")
    app.key("f", "opt", "shift")
    state = app.bar_type("beta")
    x, y = app.point_in_output(1, column=0, state=state)
    assert app.drag(x - 2, y, x + 8 * 4 - 4, y)["selectedText"] == "beta"


def test_blk_180_filter_includes_output_right_up_to_the_end(app):
    app.type("(echo keep-1; sleep 0.4; echo keep-2)")
    app.key("return")
    app.wait("the first line", lambda s: s["blocks"] and "keep-1" in s["blocks"][0]["output"])
    app.key("f", "opt", "shift")
    app.bar_type("keep")
    app.wait("the last line", lambda s: s["displayRows"] == ["keep-1", "keep-2"])
