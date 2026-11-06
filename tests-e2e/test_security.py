"""Security checks that need the app, its editor, and its private pasteboard."""
import os

from harness import App


def test_security_private_command_is_absent_from_history_and_other_panes():
    with App(zshrc="setopt HIST_IGNORE_SPACE\n") as app:
        app.run(" echo rewarp_private_command")
        assert app.type("echo rewarp_private")["ghost"] is None
        state = app.key("up")
        assert not any("rewarp_private_command" in item for item in state["menuItems"])
        app.key("escape")
        app.key("a", "cmd")
        app.key("backspace")
        app.key("d", "cmd")
        app.ready()
        assert app.type("echo rewarp_private")["ghost"] is None
        state = app.key("r", "ctrl")
        assert not any("rewarp_private_command" in item for item in state["menuItems"])


def test_security_output_cannot_read_or_replace_clipboard(app):
    sentinel = "rewarp-private-clipboard-sentinel"
    app.set_pasteboard(sentinel)
    # Clipboard replies would be read as keyboard input by this process. Disable
    # echo and collect any reply before returning to the shell.
    script = os.path.join(app.home, "clipboard.py")
    with open(script, "w") as handle:
        handle.write("""import os, select, termios, tty
old = termios.tcgetattr(0)
try:
    tty.setraw(0)
    os.write(1, b'\\x1b]52;c;?\\x07\\x1b]52;c;cmVwbGFjZWQ=\\x1b\\\\')
    ready, _, _ = select.select([0], [], [], 0.5)
    reply = os.read(0, 65536) if ready else b''
finally:
    termios.tcsetattr(0, termios.TCSANOW, old)
print('REPLY:' + reply.hex())
""")
    state = app.run(f"/usr/bin/python3 '{script}'")
    assert state["pasteboard"] == sentinel
    output = state["blocks"][-1]["output"]
    assert output.strip() == "REPLY:"


def test_security_hostile_filename_completion_is_literal(app):
    name = "hostile$(touch REWARP_COMPLETION_EXECUTED)"
    with open(os.path.join(app.home, name), "w") as handle:
        handle.write("literal-file-contents")
    app.type("cat hosti")
    app.key("tab")
    app.key("return")
    state = app.wait("literal filename output", lambda s: s["blocks"] and not s["blocks"][-1]["running"])
    assert state["blocks"][-1]["output"] == "literal-file-contents"
    assert not os.path.exists(os.path.join(app.home, "REWARP_COMPLETION_EXECUTED"))


def test_security_resizing_during_output_keeps_the_app_responsive(app):
    script = os.path.join(app.home, "resize-output.py")
    with open(script, "w") as handle:
        handle.write("""import os, time
for _ in range(2000):
    os.write(1, b'\\x1b[31moutput during resize\\x1b[0m\\r\\n')
    time.sleep(0.001)
print('RESIZE_FINISHED')
""")
    app.type(f"/usr/bin/python3 '{script}'")
    app.key("return")
    app.wait("output to start", lambda s: s["blocks"] and s["blocks"][-1]["running"])
    for width, height in [(500, 400), (1100, 700), (700, 500)] * 4:
        app.resize_window(width, height)
    state = app.wait("output after resizing", lambda s: s["blocks"] and not s["blocks"][-1]["running"])
    assert "RESIZE_FINISHED" in state["blocks"][-1]["output"]
    assert app.run("echo still_responsive")["blocks"][-1]["output"] == "still_responsive"
