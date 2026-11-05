"""End-to-end checks of tabs. IDs refer to docs/warp-parity.md."""
from harness import App


def center(frame):
    return frame[0] + frame[2] / 2, frame[1] + frame[3] / 2


def open_tabs(app, count):
    for number in range(count - 1):
        app.key("t", "cmd")
        app.wait("the new tab", lambda s: s["tabs"] == number + 2)


def name_tabs(app, names):
    """Gives each tab a distinct title, so that order can be checked."""
    for index, name in enumerate(names):
        app.key(str(index + 1), "cmd")
        app.menu("Tabs", "Rename Tab")
        app.key("a", "cmd")
        app.type(name)
        app.key("return")
    app.key("1", "cmd")
    return app.state()


def test_tab_001_cmd_t_opens_a_tab(app):
    assert app.key("t", "cmd")["tabs"] == 2


def test_tab_002_new_tabs_open_beside_the_current_one(app):
    open_tabs(app, 3)
    name_tabs(app, ["a", "b", "c"])
    app.key("1", "cmd")
    app.key("t", "cmd")
    state = app.wait("the tab", lambda s: s["tabs"] == 4)
    assert state["selectedTab"] == 1


def test_tab_009_cycle_tabs(app):
    open_tabs(app, 2)
    app.key("1", "cmd")
    assert app.menu("Tabs", "Next Tab")["selectedTab"] == 1
    assert app.menu("Tabs", "Previous Tab")["selectedTab"] == 0


def test_tab_010_ctrl_tab_switches_tabs(app):
    open_tabs(app, 2)
    app.key("1", "cmd")
    assert app.key("tab", "ctrl")["selectedTab"] == 1
    assert app.key("tab", "ctrl", "shift")["selectedTab"] == 0


def test_tab_013_cmd_numbers(app):
    open_tabs(app, 3)
    assert app.key("1", "cmd")["selectedTab"] == 0
    assert app.key("2", "cmd")["selectedTab"] == 1
    assert app.key("9", "cmd")["selectedTab"] == 2


def test_tab_014_keyboard_moves_a_tab(app):
    open_tabs(app, 2)
    name_tabs(app, ["a", "b"])
    state = app.key("right", "ctrl", "shift")
    assert state["tabTitles"] == ["b", "a"]
    assert state["selectedTab"] == 1
    assert app.key("left", "ctrl", "shift")["tabTitles"] == ["a", "b"]


def test_mou_088_drag_reorders_tabs(app):
    open_tabs(app, 3)
    state = name_tabs(app, ["a", "b", "c"])
    x1, y1 = center(state["tabFrames"][0])
    x3, y3 = center(state["tabFrames"][2])
    assert app.drag(x1, y1, x3, y3)["tabTitles"] == ["b", "c", "a"]


def test_mou_082_double_click_renames(app):
    state = app.state()
    x, y = center(state["tabFrames"][0])
    assert app.click(x, y, count=2)["renaming"]
    app.key("a", "cmd")
    app.type("server")
    state = app.key("return")
    assert state["tabTitles"] == ["server"]
    assert not state["renaming"]


def test_tab_017_renaming_refocuses_the_input(app):
    app.menu("Tabs", "Rename Tab")
    app.key("a", "cmd")
    app.type("server")
    assert app.key("return")["focus"] == "input"


def test_vtb_017_escape_cancels_a_rename(app):
    before = app.state()["tabTitles"]
    app.menu("Tabs", "Rename Tab")
    app.key("a", "cmd")
    app.type("nope")
    assert app.key("escape")["tabTitles"] == before


def test_tab_018_custom_title_survives_a_pane_switch(app):
    app.menu("Tabs", "Rename Tab")
    app.key("a", "cmd")
    app.type("server")
    app.key("return")
    app.key("d", "cmd")
    state = app.wait("the split", lambda s: s["panes"] == 2)
    assert state["tabTitles"] == ["server"]


def test_tab_004_cmd_w_closes_the_pane_then_the_tab(app):
    app.key("t", "cmd")
    app.wait("two tabs", lambda s: s["tabs"] == 2)
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2)
    assert app.key("w", "cmd")["panes"] == 1
    assert app.key("w", "cmd")["tabs"] == 1


def test_tab_016_close_actions_in_the_menu(app):
    open_tabs(app, 3)
    name_tabs(app, ["a", "b", "c"])
    app.key("2", "cmd")
    assert app.menu("Tabs", "Close Tabs to the Right")["tabTitles"] == ["a", "b"]
    assert app.menu("Tabs", "Close Other Tabs")["tabTitles"] == ["b"]


def test_tab_007_reopen_closed_tab(app):
    app.key("t", "cmd")
    app.wait("two tabs", lambda s: s["tabs"] == 2)
    assert app.key("w", "cmd")["tabs"] == 1
    assert app.key("t", "cmd", "shift")["tabs"] == 2


def test_vtb_001_tabs_can_move_to_a_left_sidebar(app):
    state = app.menu("View", "Tab Bar on Left")
    assert state["tabPosition"] == "left"
    assert state["tabFrames"][0][0] == 0
    assert state["paneFrame"][0] > 100


def test_tabs_can_move_to_a_right_sidebar(app):
    state = app.menu("View", "Tab Bar on Right")
    assert state["tabPosition"] == "right"
    assert state["tabFrames"][0][0] > 400
    assert state["paneFrame"][0] == 0


def test_tabs_can_return_to_the_top(app):
    app.menu("View", "Tab Bar on Left")
    state = app.menu("View", "Tab Bar on Top")
    assert state["tabPosition"] == "top"
    assert state["paneFrame"][0] == 0


def test_sidebar_tabs_stack_vertically(app):
    open_tabs(app, 3)
    frames = app.menu("View", "Tab Bar on Left")["tabFrames"]
    assert frames[0][1] < frames[1][1] < frames[2][1]
    assert frames[0][0] == frames[1][0]


def test_vtb_022_tab_shortcuts_work_in_a_sidebar(app):
    open_tabs(app, 2)
    app.menu("View", "Tab Bar on Right")
    assert app.key("1", "cmd")["selectedTab"] == 0
    assert app.key("tab", "ctrl")["selectedTab"] == 1


def test_sidebar_drag_reorders_on_both_sides(app):
    for side in ["Left", "Right"]:
        open_tabs(app, 2)
        name_tabs(app, ["a", "b"])
        state = app.menu("View", f"Tab Bar on {side}")
        x1, y1 = center(state["tabFrames"][0])
        x2, y2 = center(state["tabFrames"][1])
        assert app.drag(x1, y1, x2, y2)["tabTitles"] == ["b", "a"]
        app.menu("Tabs", "Close Other Tabs")


def test_vtb_019_double_clicking_empty_sidebar_opens_a_tab(app):
    state = app.menu("View", "Tab Bar on Left")
    frame = state["tabFrames"][0]
    state = app.click(frame[0] + 40, frame[1] + 300, count=2)
    assert app.wait("the new tab", lambda s: s["tabs"] == 2)


def test_tabs_work_after_moving_a_terminal_in_a_sidebar(app):
    app.menu("View", "Tab Bar on Left")
    state = app.run("echo still-works")
    assert state["blocks"][0]["output"] == "still-works"


def test_closing_a_pane_running_a_flood_keeps_the_app_alive(app):
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2 and s["phase"] == "ready")
    app.type("yes")
    app.key("return")
    app.wait("the flood", lambda s: s["blocks"] and s["blocks"][-1]["rows"] > 100)
    state = app.key("w", "cmd")
    assert state["panes"] == 1
    assert app.run("echo alive")["blocks"][-1]["output"] == "alive"


def test_closing_a_pane_running_a_quiet_program_does_not_freeze(app):
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2 and s["phase"] == "ready")
    app.type("sleep 1000")
    app.key("return")
    app.wait("the block", lambda s: s["blocks"] and s["blocks"][-1]["running"])
    assert app.key("w", "cmd")["panes"] == 1
    assert app.run("echo alive")["blocks"][-1]["output"] == "alive"


def test_closing_a_zoomed_pane_keeps_the_rest_of_the_tab(app):
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2)
    app.key("return", "cmd", "shift")
    state = app.key("w", "cmd")
    assert state["tabs"] == 1
    assert state["panes"] == 1


def test_running_programs_keep_their_shortcut_keys(app):
    app.run("true")
    app.type("cat")
    app.key("return")
    app.wait("the input to hide", lambda s: s["inputHidden"] and s["focus"] == "terminal")
    state = app.key("up", "opt")
    assert state["selected"] == []
    app.wait("the key to reach cat", lambda s: "[1;3A" in s["blocks"][-1]["output"])


def test_moving_focus_out_of_a_zoomed_pane_shows_the_pane(app):
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2)
    app.key("return", "cmd", "shift")
    app.wait("the zoom", lambda s: s["paneFrame"][2] == s["windowFrame"][0])
    state = app.key("]", "cmd")
    assert state["focus"] == "input"
    assert not state["paneHidden"]


def test_closing_a_window_frees_its_panes():
    with App() as app:
        app.ready()
        app.key("n", "cmd")
        app.wait("the second window", lambda s: s["windows"] == 2 and s["liveTerminals"] == 2)
        app._command(cmd="closeWindow")
        state = app.wait("the panes to go", lambda s: s["liveTerminals"] == 1)
        assert state["windows"] == 1
