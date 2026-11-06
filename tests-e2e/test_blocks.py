"""End-to-end checks of block behaviour. IDs refer to docs/warp-parity.md."""
import os
import shutil
import tempfile
import time

from harness import App


def test_blk_001_command_creates_block(app):
    state = app.run("echo hello")
    block = state["blocks"][0]
    assert block["command"] == "echo hello"
    assert block["output"] == "hello"
    assert block["exit"] == 0


def test_blk_002_new_blocks_land_above_input_older_move_up(app):
    first = app.run("echo one")
    y_before = app.frame(1, first)["top"]
    second = app.run("echo two")
    assert app.frame(1, second)["top"] < y_before
    assert app.frame(2, second)["bottom"] <= second["listHeight"] / 2 + 1


def test_blk_023_failed_command_is_marked(app):
    assert app.run("false")["blocks"][-1]["failed"]


def test_blk_024_missing_command_is_failed(app):
    assert app.run("this-does-not-exist-xyz")["blocks"][-1]["failed"]


def test_cor_004_nothing_reaches_shell_until_enter(app):
    state = app.type("echo pending")
    assert state["input"] == "echo pending"
    assert state["blocks"] == []


def test_cor_008_typing_during_bootstrap_is_kept():
    with App() as app:
        app.type("echo early")
        app.key("return")
        state = app.wait("the early command", lambda s: len(s["blocks"]) == 1 and not s["blocks"][0]["running"])
        assert state["blocks"][0]["output"] == "early"


def replaced_shell_settles(app):
    return app.wait("the new shell's prompt", lambda s: s["phase"] == "ready" and not s["blocks"][-1]["running"])


def test_exec_zsh_gets_back_to_blocks_and_the_input(app):
    app.type("exec zsh")
    app.key("return")
    state = replaced_shell_settles(app)
    assert [b["command"] for b in state["blocks"]] == ["exec zsh"]
    assert not state["inputHidden"]
    assert state["focus"] == "input"

    state = app.run("echo after")
    assert state["blocks"][-1]["output"] == "after"
    assert state["blocks"][-1]["exit"] == 0


def test_omz_reload_gets_back_to_blocks_and_the_input():
    # What oh-my-zsh runs, which takes the login branch in a pane.
    with App(zshrc="""reload() {
      local zsh="$ZSH_ARGZERO"
      [[ "${zsh#-}" != /* ]] && (( $+commands[zsh] )) && zsh="zsh"
      [[ "$zsh" = -* || -o login ]] && exec -l "${zsh#-}" || exec "$zsh"
    }""") as app:
        app.ready()
        app.type("reload")
        app.key("return")
        assert not replaced_shell_settles(app)["inputHidden"]
        assert app.run("[[ -o login ]] && echo login")["blocks"][-1]["output"] == "login"


def test_blk_032_click_selects_block(app):
    state = app.run("echo one")
    x, y = app.point_in_output(1, state=state)
    state = app.click(x, y)
    assert state["selected"] == [1]
    assert state["active"] == 1


def test_cor_014_selecting_moves_focus_to_block_list(app):
    state = app.run("echo one")
    x, y = app.point_in_output(1, state=state)
    assert app.click(x, y)["focus"] == "terminal"


def test_blk_033_cmd_up_selects_latest(app):
    app.run("echo one")
    app.run("echo two")
    state = app.key("up", "cmd")
    assert state["selected"] == [2]
    assert state["focus"] == "terminal"


def test_blk_034_arrows_move_between_blocks(app):
    app.run("echo one")
    app.run("echo two")
    app.key("up", "cmd")
    assert app.key("up")["selected"] == [1]
    assert app.key("down")["selected"] == [2]


def test_cor_018_cmd_down_past_latest_returns_to_input(app):
    app.run("echo one")
    app.key("up", "cmd")
    state = app.key("down", "cmd")
    assert state["selected"] == []
    assert state["focus"] == "input"


def test_blk_035_cmd_click_toggles(app):
    app.run("echo one")
    state = app.run("echo two")
    x1, y1 = app.point_in_output(1, state=state)
    x2, y2 = app.point_in_output(2, state=state)
    app.click(x1, y1)
    assert app.click(x2, y2, "cmd")["selected"] == [1, 2]
    assert app.click(x1, y1, "cmd")["selected"] == [2]


def test_blk_036_shift_click_selects_range(app):
    app.run("echo one")
    app.run("echo two")
    state = app.run("echo three")
    x1, y1 = app.point_in_output(1, state=state)
    x3, y3 = app.point_in_output(3, state=state)
    app.click(x1, y1)
    assert app.click(x3, y3, "shift")["selected"] == [1, 2, 3]


def test_blk_037_shift_arrows_extend(app):
    app.run("echo one")
    app.run("echo two")
    app.run("echo three")
    app.key("up", "cmd")
    assert app.key("up", "shift")["selected"] == [2, 3]
    assert app.key("up", "shift")["selected"] == [1, 2, 3]


def test_mou_025_drag_makes_text_selection_not_block_selection(app):
    state = app.run("echo hello-world")
    x, y = app.point_in_output(1, column=0, state=state)
    state = app.drag(x - 2, y, x + 8 * 5 - 4, y)
    assert state["selectedText"] == "hello"
    assert state["selected"] == []


def test_mou_001_copy_on_select(app):
    state = app.run("echo hello-world")
    x, y = app.point_in_output(1, column=0, state=state)
    assert app.drag(x - 2, y, x + 8 * 5 - 4, y)["pasteboard"] == "hello"


def test_mou_024_triple_click_selects_line(app):
    state = app.run("echo 'one two three'")
    x, y = app.point_in_output(1, column=4, state=state)
    assert app.click(x, y, count=3)["selectedText"] == "one two three"


def test_blk_072_cmd_c_copies_output_of_selected_block(app):
    state = app.run("echo copied")
    x, y = app.point_in_output(1, state=state)
    app.click(x, y)
    assert app.key("c", "cmd")["pasteboard"] == "copied"


def test_blk_073_copy_command(app):
    app.run("echo copied")
    app.key("up", "cmd")
    app.menu("Blocks", "Copy Command")
    assert app.state()["pasteboard"] == "echo copied"


def test_blk_083_bookmark_toggle(app):
    app.run("echo one")
    app.key("up", "cmd")
    assert app.key("b", "cmd")["blocks"][0]["bookmarked"]
    assert not app.key("b", "cmd")["blocks"][0]["bookmarked"]


def test_blk_088_jump_between_bookmarks(app):
    app.run("echo one")
    app.run("echo two")
    app.run("echo three")
    app.key("up", "cmd")
    app.key("up")
    app.key("up")
    app.key("b", "cmd")
    app.key("down", "cmd")
    app.key("down", "cmd")
    assert app.key("up", "opt")["selected"] == [1]


def test_blk_134_reinput(app):
    app.run("echo again")
    app.key("up", "cmd")
    state = app.key("i", "cmd")
    assert state["input"] == "echo again"
    assert state["focus"] == "input"
    assert state["selected"] == []


def test_blk_139_cmd_k_clears_all_blocks(app):
    app.run("echo one")
    app.run("echo two")
    app.key("k", "cmd")
    assert app.wait("blocks to clear", lambda s: s["blocks"] == [] and s["contentHeight"] == 0)


def test_blk_029_ctrl_c_in_empty_input_keeps_shell_usable(app):
    app.type("half typed")
    state = app.key("c", "ctrl")
    assert state["input"] == ""
    assert app.run("echo fine")["blocks"][0]["output"] == "fine"


def test_blk_065_context_menu_items(app):
    state = app.run("echo one")
    x, y = app.point_in_output(1, state=state)
    menu = app.click(x, y, button="right")["contextMenu"]
    for item in ["Copy Command", "Copy Output", "Copy Both", "Copy Working Directory", "Toggle Bookmark", "Reinput",
                 "Split Pane Right", "Split Pane Down", "Close Pane", "Paste", "Clear"]:
        assert item in menu


def test_blk_068_context_menu_offers_copy_with_text_selected(app):
    state = app.run("echo hello-world")
    x, y = app.point_in_output(1, column=0, state=state)
    app.drag(x - 2, y, x + 8 * 5 - 4, y)
    assert app.click(x, y, button="right")["contextMenu"][:2] == ["Copy", "Insert into Input"]


def test_blk_045_scrolling_and_following_output(app):
    state = app.run("seq 1 200")
    assert state["contentHeight"] > state["listHeight"]
    assert state["followsTail"]
    x, y = 200, 200
    state = app.scroll(x, y, 400)
    assert not state["followsTail"]
    assert state["scrollOffset"] < state["contentHeight"] - state["listHeight"]


def test_blk_047_home_and_end(app):
    app.run("seq 1 200")
    app.key("up", "cmd")
    assert app.key("home")["scrollOffset"] == 0
    state = app.key("end")
    assert state["followsTail"]


def test_blk_159_full_screen_program_takes_over(app):
    app.type("printf '\\033[?1049h'; sleep 0.6; printf '\\033[?1049l'")
    app.key("return")
    state = app.wait("the full-screen display", lambda s: s["display"] == "fullscreen")
    assert state["inputHidden"]
    app.wait("the list and input to return", lambda s: s["display"] == "list" and not s["inputHidden"])


def test_cor_032_keys_reach_a_running_program(app):
    app.type("cat")
    app.key("return")
    app.wait("the input to hide", lambda s: s["inputHidden"] and s["focus"] == "terminal")
    app.type("typed-into-cat")
    app.key("return")
    app.wait("the echo", lambda s: "typed-into-cat" in s["blocks"][-1]["output"])
    app.key("d", "ctrl")
    state = app.wait("cat to exit", lambda s: s["phase"] == "ready")
    assert state["focus"] == "input"


def test_cor_040_fast_commands_do_not_hide_the_input(app):
    heights = set()
    app.type("true")
    app.key("return")
    for _ in range(20):
        state = app.state()
        heights.add(state["inputHidden"])
    assert heights == {False}


def test_mou_017_clicking_a_running_block_does_not_select_it(app):
    app.type("sleep 5")
    app.key("return")
    state = app.wait("the block", lambda s: len(s["blocks"]) == 1)
    frame = app.frame(1, app.wait("frames", lambda s: s["blockFrames"]))
    state = app.click(200, app.state()["paneFrame"][1] + frame["top"] + 12)
    assert state["selected"] == []


def test_blk_147_a_block_holds_up_to_50000_rows(app):
    state = app.run("seq 1 60000")
    rows = state["blocks"][0]["rows"]
    assert 49000 <= rows <= 51000, rows
    assert state["blocks"][0]["output"].endswith("60000")


def test_long_output_is_kept_in_full(app):
    state = app.run("seq 1 20000")
    assert state["blocks"][0]["output"].startswith("1\n2\n")


def test_a_tall_block_with_its_header_far_off_screen_keeps_drawing(app):
    state = app.run("seq 1 3000")
    assert state["contentHeight"] > 70000
    assert app.run("echo after")["blocks"][-1]["output"] == "after"


def test_a_tall_running_block_keeps_drawing(app):
    app.type("seq 1 3000; sleep 1")
    app.key("return")
    state = app.wait("the output", lambda s: s["blocks"] and s["blocks"][-1]["rows"] >= 3000)
    assert state["blocks"][-1]["running"]
    app.wait("the command to finish", lambda s: s["phase"] == "ready", timeout=5)


def test_a_tall_failed_and_selected_block_keeps_drawing(app):
    state = app.run("seq 1 3000; false")
    assert state["blocks"][-1]["failed"]
    assert app.key("up", "cmd")["selected"] == [1]
    assert app.key("b", "cmd")["blocks"][0]["bookmarked"]


def text_origin(state):
    """A point on the first row of a plain or full-screen terminal."""
    x, y, _, _ = state["paneFrame"]
    return x + 14 + 2, y + 8 + 6


def test_plain_terminal_selection_copies_and_clears():
    with App(shell="/bin/bash") as app:
        state = app.wait("bash", lambda s: s["display"] == "plain" and s["focus"] == "terminal", timeout=10)
        x, y = text_origin(state)
        y += 16  # bash's banner starts on the second row
        app.wait("the banner", lambda _: app.drag(x, y, x + 8 * 6, y)["selectedText"])
        selected = app.state()
        assert selected["selectedText"]
        assert selected["pasteboard"] == selected["selectedText"]
        assert app.click(x + 8 * 3, y + 60)["selectedText"] is None


def test_a_shell_without_integration_stays_a_plain_terminal():
    with App(shell="/bin/bash") as app:
        app.wait("bash", lambda s: s["display"] == "plain" and s["focus"] == "terminal", timeout=10)
        app.type(r"printf '\033]133;A\007\033]133;B\007\033]133;C;cmdline_url=fake\007'")
        app.key("return")
        time.sleep(0.4)
        state = app.state()
        assert state["phase"] == "plain"
        assert state["display"] == "plain"
        assert state["blocks"] == []


def test_a_shell_that_cant_get_its_token_ends_up_a_plain_terminal():
    # Named zsh, so it's launched with integration, but it has no way to ask.
    directory = tempfile.mkdtemp(prefix="rewarp-e2e-")
    shell = os.path.join(directory, "zsh")
    with open(shell, "w") as f:
        f.write("#!/bin/sh\nunset REWARP_SOCKET\nexec /bin/zsh -il\n")
    os.chmod(shell, 0o755)
    try:
        with App(shell=shell) as app:
            app.wait("the terminal", lambda s: s["display"] == "plain" and s["focus"] == "terminal", timeout=10)
            app.type("touch typed")
            app.key("return")
            deadline = time.time() + 5
            while not os.path.exists(os.path.join(app.home, "typed")) and time.time() < deadline:
                time.sleep(0.02)
            assert os.path.exists(os.path.join(app.home, "typed"))
            assert app.state()["phase"] == "plain"
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def test_selection_in_a_filtered_running_block_outlives_its_refresh(app):
    app.type("while true; do echo tick; sleep 0.05; done")
    app.key("return")
    app.wait("output", lambda s: s["blocks"] and "tick" in s["blocks"][0]["output"])
    app.key("f", "opt", "shift")
    app.bar_type("tick")
    frame = app.wait("the block", lambda s: s["blockFrames"])["blockFrames"][0]
    pane = app.state()["paneFrame"]
    x = pane[0] + 14 + 2
    y = pane[1] + frame["outputTop"] + 6
    assert app.drag(x, y, x + 8 * 3, y)["selectedText"]
    time.sleep(0.4)
    assert app.state()["selectedText"]
    app.key("c", "ctrl")


def test_middle_click_pastes_into_a_running_program(app):
    app.set_pasteboard("from-the-clipboard")
    app.type("cat")
    app.key("return")
    state = app.wait("the input to hide", lambda s: s["inputHidden"] and s["focus"] == "terminal")
    x, y = text_origin(state)
    app.click(x, y + 100, button="middle")
    app.wait("cat to echo it", lambda s: "from-the-clipboard" in s["blocks"][-1]["output"])
    assert app.state()["input"] == ""


def test_output_marks_can_not_end_a_block_in_the_app(app):
    state = app.run(r"printf '\e]133;D;0\a\e]133;A\a'; sleep 0.3; echo still-mine")
    assert len(state["blocks"]) == 1
    assert state["blocks"][0]["output"] == "still-mine"


def test_moving_to_a_display_of_another_density_keeps_the_text_size():
    with App() as app:
        def size():
            return [int(n) for n in app.run("stty size")["blocks"][-1]["output"].split()]
        rows, columns = size()
        app._command(cmd="setScale", scale=1.0)
        new_rows, new_columns = size()
        # Cell sizes round differently, but the text has to stay the same size.
        assert abs(new_rows - rows) <= rows * 0.1
        assert abs(new_columns - columns) <= columns * 0.1


def test_finished_blocks_survive_the_glyph_atlas_filling_up(app):
    """Panes share the atlas, so the idle one is what would show stale glyphs."""
    app.key("d", "cmd")
    app.wait("the split", lambda s: s["panes"] == 2 and s["focus"] == "input")
    app.key("]", "cmd")
    app.run("echo hello world")
    first = os.path.join(app.home, "first.png")
    second = os.path.join(app.home, "second.png")
    app._command(cmd="capture", path=first)
    app.key("]", "cmd")
    # More distinct glyphs than the atlas holds, all of them drawn.
    for round in range(12):
        app.run(f"python3 -c \"print(''.join(chr(0x4e00 + {round} * 800 + i) for i in range(800)))\"")
    app.key("]", "cmd")
    app._command(cmd="capture", path=second)
    with open(first, "rb") as a, open(second, "rb") as b:
        assert a.read() == b.read()


def test_a_question_from_startup_files_can_be_seen_and_answered():
    zshrc = 'print -n "Update now? [Y/n] "; read -k 1 answer; print; print "answered $answer"\n'
    with App(zshrc=zshrc) as app:
        state = app.wait("the question", lambda s: s["display"] == "plain" and s["focus"] == "terminal")
        assert state["inputHidden"]
        app.type("y")
        state = app.wait("the prompt", lambda s: s["phase"] == "ready" and s["display"] == "list")
        assert app.wait("the input", lambda s: s["focus"] == "input" and not s["inputHidden"])
        assert app.run("echo fine")["blocks"][-1]["output"] == "fine"


def test_a_slow_but_silent_start_keeps_the_input():
    with App(zshrc="sleep 2.5\n") as app:
        time.sleep(2.3)
        state = app.state()
        assert state["phase"] == "plain"
        assert not state["inputHidden"]
        assert state["display"] == "list"
        app.ready()
