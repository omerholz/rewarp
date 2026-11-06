"""Drives the real app through its control channel.

Each App gets its own HOME, so nothing depends on this machine's dotfiles, its own
pasteboard, so the user's clipboard is never touched, and its own TMPDIR, because a
killed app leaves its sockets behind.
"""
import json
import os
import shutil
import subprocess
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARY = os.path.join(ROOT, ".build", "debug", "Rewarp")

KEY = {
    "return": 36, "tab": 48, "backspace": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "a": 0, "b": 11, "c": 8, "d": 2, "f": 3, "g": 5, "i": 34, "j": 38, "k": 40, "l": 37, "p": 35, "r": 15,
    "s": 1, "t": 17, "w": 13, "n": 45, "1": 18, "2": 19, "3": 20, "9": 25, "]": 30,
}


# The last state any app reported, so that a failed assertion can show it.
last_state = {}


class App:
    def __init__(self, zshrc="", history="", shell="/bin/zsh", environment=None, startup_files=None):
        self.home = tempfile.mkdtemp(prefix="rewarp-e2e-")
        with open(os.path.join(self.home, ".zshrc"), "w") as f:
            f.write(zshrc)
        with open(os.path.join(self.home, ".zsh_history"), "w") as f:
            f.write(history)
        for name, contents in (startup_files or {}).items():
            path = os.path.join(self.home, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(contents)
        self.fifo = os.path.join(self.home, "control")
        os.mkfifo(self.fifo)
        env = dict(os.environ, HOME=self.home, TMPDIR=self.home, REWARP_CONTROL=self.fifo,
                   XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
                   XDG_DATA_HOME=os.path.join(self.home, ".local", "share"),
                   HISTFILE=os.path.join(self.home, ".zsh_history"))
        env.pop("ZDOTDIR", None)
        env.update(environment or {})
        if shell:
            env["REWARP_SHELL"] = shell
        self.process = subprocess.Popen([BINARY], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=self.home)
        self.writer = None
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                self.writer = os.open(self.fifo, os.O_WRONLY | os.O_NONBLOCK)
                break
            except OSError:
                time.sleep(0.02)
        assert self.writer is not None, "control channel never opened"

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
        if self.writer is not None:
            os.close(self.writer)
        shutil.rmtree(self.home, ignore_errors=True)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def _command(self, **command):
        reply = self.fifo + ".reply"
        if os.path.exists(reply):
            os.remove(reply)
        os.write(self.writer, (json.dumps(command) + "\n").encode())
        deadline = time.time() + 5
        while time.time() < deadline:
            if os.path.exists(reply):
                with open(reply) as f:
                    global last_state
                    last_state = json.load(f)
                    return last_state
            if self.process.poll() is not None:
                raise AssertionError(f"app exited with {self.process.returncode}")
            time.sleep(0.005)
        raise AssertionError(f"no reply to {command}")

    def state(self):
        return self._command(cmd="state")

    def wait(self, what, predicate, timeout=8):
        deadline = time.time() + timeout
        state = None
        while time.time() < deadline:
            state = self.state()
            if predicate(state):
                return state
            time.sleep(0.02)
        raise AssertionError(f"timed out waiting for {what}: {json.dumps(state)[:800]}")

    def ready(self):
        return self.wait("the prompt", lambda s: s["phase"] == "ready")

    def type(self, text):
        return self._command(cmd="type", text=text)

    def key(self, name, *mods):
        return self._command(cmd="key", code=KEY[name], mods=list(mods))

    def run(self, command):
        """Types a command, presses Enter, and waits for its block to finish."""
        count = len(self.ready()["blocks"])
        self.type(command)
        self.key("return")
        self.wait(f"`{command}` to finish", lambda s: len(s["blocks"]) > count
                  and not s["blocks"][-1]["running"] and s["phase"] == "ready")
        # Once more, because a state lays out the frame before it reads the blocks,
        # so the one that saw the block finish can hold the layout from just before.
        return self.state()

    def click(self, x, y, *mods, count=1, button="left"):
        return self._command(cmd="click", x=x, y=y, mods=list(mods), count=count, button=button)

    def drag(self, x1, y1, x2, y2, *mods):
        return self._command(cmd="drag", x1=x1, y1=y1, x2=x2, y2=y2, mods=list(mods))

    def resize_window(self, width, height):
        return self._command(cmd="resizeWindow", width=width, height=height)

    def press(self, x, y):
        return self._command(cmd="press", x=x, y=y)

    def drag_to(self, x, y):
        return self._command(cmd="dragTo", x=x, y=y)

    def release(self, x, y):
        return self._command(cmd="release", x=x, y=y)

    def move(self, x, y):
        return self._command(cmd="move", x=x, y=y)

    def scroll(self, x, y, dy):
        return self._command(cmd="scroll", x=x, y=y, dy=dy)

    def menu(self, *path):
        return self._command(cmd="menu", path=list(path))

    def bar_type(self, text):
        return self._command(cmd="barType", text=text)

    def palette_type(self, text):
        return self._command(cmd="paletteType", text=text)

    def set_pasteboard(self, text):
        return self._command(cmd="pasteboard", text=text)

    def capture(self, path):
        return self._command(cmd="capture", path=path)

    def frame(self, block_id, state=None):
        state = state or self.state()
        for frame in state["blockFrames"]:
            if frame["id"] == block_id:
                return frame
        raise AssertionError(f"block {block_id} is not on screen")

    def point_in_output(self, block_id, column=2, row=0, state=None):
        """Window coordinates for a cell in a block's output."""
        state = state or self.state()
        frame = self.frame(block_id, state)
        pane_x, pane_y = state["paneFrame"][0], state["paneFrame"][1]
        return pane_x + 14 + column * 8 + 4, pane_y + frame["outputTop"] + row * 16 + 8
