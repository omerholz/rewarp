#!/usr/bin/env python3
"""Leaves a visible app running in a scripted state, for looking at."""
import json
import os
import subprocess
import sys
import tempfile
import time

HOME = tempfile.mkdtemp(prefix="rewarp-visual-")
fifo = os.path.join(HOME, "control")
os.mkfifo(fifo)
binary = sys.argv[1]
script = json.loads(sys.argv[2])
env = dict(os.environ, REWARP_CONTROL=fifo, REWARP_VISIBLE="1")
process = subprocess.Popen([binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           cwd=sys.argv[3] if len(sys.argv) > 3 else None, start_new_session=True)
time.sleep(1.5)
writer = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
for command in script:
    os.write(writer, (json.dumps(command) + "\n").encode())
    time.sleep(command.get("wait", 0.25))
print(process.pid)
