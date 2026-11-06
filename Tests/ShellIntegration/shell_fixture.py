"""Real shells on a PTY with a minimal protocol peer, usable on Linux and macOS.

Native app tests separately verify peer credentials and UI routing. This peer is
only a shell-adapter fixture; it intentionally does not emulate authentication.
"""
import errno
import os
from pathlib import Path
import pty
import re
import select
import signal
import socket
import struct
import tempfile
import threading
import time
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = os.environ.get("REWARP_SHELL_BRIDGE", str(ROOT / ".build/debug/RewarpShellBridge"))
TOKEN = "test-shell-token"
REPORT = re.compile(rb"\x1b\]7701;([a-z]+)=test-shell-token;([^\x07]*)\x07")


class ShellFixture:
    def __init__(self, shell="zsh", startup=None, environment=None, argv=None, initial_input=None):
        self.directory = tempfile.TemporaryDirectory(prefix="rw-shell-")
        self.home = Path(self.directory.name)
        for name, contents in (startup or {}).items():
            path = self.home / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.home / "token.sock"))
        self.listener.listen(4)
        self.listener.settimeout(0.1)
        self.stopped = threading.Event()
        env = {key: value for key, value in os.environ.items() if not key.startswith("REWARP_")}
        env.update(HOME=str(self.home), TERM="xterm-256color",
                   XDG_CONFIG_HOME=str(self.home / ".config"), XDG_DATA_HOME=str(self.home / ".local/share"),
                   ZDOTDIR=str(ROOT / "resources/shell-integration/zsh"),
                   REWARP_SOCKET=str(self.home / "token.sock"), REWARP_SHELL_HELPER=BRIDGE)
        env.pop("REWARP_USER_ZDOTDIR", None)
        env.update(environment or {})
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(self.home)
            os.execvpe(shell, argv or ["-" + Path(shell).name], env)
        self.helper_parents = []
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        if initial_input:
            os.write(self.fd, initial_input.encode())
        self.output = b""
        self.events = []
        self.parsed = 0

    def serve(self):
        while not self.stopped.is_set():
            try:
                client, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with client:
                if hasattr(socket, "SO_PEERCRED"):
                    peer = struct.unpack("3i", client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[0]
                    if peer != self.pid:
                        status = Path(f"/proc/{peer}/status").read_text()
                        self.helper_parents.append(int(re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)[1]))
                client.sendall((TOKEN + "\n").encode())

    def wait(self, predicate, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate(self.events):
                return self.events
            if not select.select([self.fd], [], [], 0.05)[0]:
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            self.output += chunk
            for match in REPORT.finditer(self.output, self.parsed):
                self.events.append((match[1].decode(), unquote(match[2].decode())))
                self.parsed = match.end()
        raise AssertionError(f"shell did not reach expected state; events={self.events[-8:]}; output={self.output[-1500:]!r}")

    def ready(self):
        self.wait(lambda events: any(key == "ready" for key, _ in events))

    def run(self, command, timeout=12):
        before = len(self.events)
        start = len(self.output)
        os.write(self.fd, command.encode() + b"\n")
        def completed(events):
            current = events[before:]
            last_done = max((i for i, (key, _) in enumerate(current) if key == "done"), default=-1)
            return last_done >= 0 and any(key == "ready" for key, _ in current[last_done + 1:])
        self.wait(completed, timeout)
        return self.output[start:], self.events[before:]

    def close(self):
        self.stopped.set()
        self.listener.close()
        try:
            os.kill(self.pid, signal.SIGHUP)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if os.waitpid(self.pid, os.WNOHANG)[0]:
                break
            time.sleep(0.02)
        else:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.fd)
        self.thread.join(timeout=1)
        self.directory.cleanup()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
