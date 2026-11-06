#!/usr/bin/env python3
"""Check the production binary statically and with automation variables set."""
import errno
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1]).resolve()
strings = subprocess.check_output(["/usr/bin/strings", "-a", str(binary)])
for marker in (b"REWARP_CONTROL", b"REWARP_SEND", b"REWARP_CAPTURE", b"REWARP_STATS", b"ControlChannel"):
    if marker in strings:
        raise SystemExit(f"production binary contains automation marker: {marker.decode()}")

with tempfile.TemporaryDirectory(prefix="rewarp-release-") as directory:
    root = Path(directory)
    (root / ".zshrc").touch()
    fifo = root / "control"
    os.mkfifo(fifo)
    env = dict(os.environ, HOME=directory, TMPDIR=directory,
               HISTFILE=str(root / ".zsh_history"), REWARP_SHELL="/bin/zsh",
               REWARP_CONTROL=str(fifo), REWARP_SEND=f"touch '{root / 'executed'}'",
               REWARP_CAPTURE=str(root / "capture.png"), REWARP_STATS=str(root / "stats"),
               REWARP_WAIT="0")
    env.pop("ZDOTDIR", None)
    process = subprocess.Popen([str(binary)], env=env, cwd=directory,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            if process.poll() is not None:
                raise AssertionError("production app exited during automation isolation check")
            assert not any((root / name).exists() for name in ("executed", "capture.png", "stats")), \
                "production app activated environment automation"
            try:
                writer = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
            except OSError as error:
                if error.errno != errno.ENXIO:
                    raise
            else:
                os.close(writer)
                raise AssertionError("production app opened the control FIFO")
            time.sleep(0.1)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
print("production automation isolation passed")
