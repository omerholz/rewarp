#!/usr/bin/env python3
"""Leaves a visible app running in a scripted state, for looking at."""
import json
import os
import subprocess
import sys
import tempfile
import time

home = tempfile.mkdtemp(prefix="rewarp-visual-")
fifo = os.path.join(home, "control")
os.mkfifo(fifo)
binary = sys.argv[1]
script = json.loads(sys.argv[2])
env = {key: value for key, value in os.environ.items() if not key.startswith("REWARP_")}
env.update(HOME=home, TMPDIR=home, HISTFILE=os.path.join(home, ".zsh_history"),
           REWARP_CONTROL=fifo, REWARP_VISIBLE="1")
env.pop("ZDOTDIR", None)
process = subprocess.Popen([binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           cwd=sys.argv[3] if len(sys.argv) > 3 else None, start_new_session=True)
time.sleep(1.5)
writer = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
for command in script:
    os.write(writer, (json.dumps(command) + "\n").encode())
    time.sleep(command.get("wait", 0.25))
print(process.pid)
