#!/usr/bin/env python3
"""A small runner, so that the end-to-end tests need nothing installed.

A test taking an `app` argument gets a fresh app at the prompt. A full run ticks
the parity IDs named by passing tests, such as `test_blk_032_...`, in
docs/warp-parity.md, so the count there can only come from a test that passed.

usage: tests-e2e/run.py [substring]
"""
import importlib
import inspect
import os
import re
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import harness  # noqa: E402
from harness import App  # noqa: E402

pattern = sys.argv[1] if len(sys.argv) > 1 else ""
tests = []
for name in sorted(os.listdir(HERE)):
    if name.startswith("test_") and name.endswith(".py"):
        module = importlib.import_module(name[:-3])
        tests += [(n, f) for n, f in vars(module).items() if n.startswith("test_") and pattern in n]

failures = []
passed = []
start = time.time()
for name, test in tests:
    try:
        if "app" in inspect.signature(test).parameters:
            with App() as app:
                app.ready()
                test(app)
        else:
            test()
        passed.append(name)
        print(f"  ok    {name}", flush=True)
    except Exception as error:
        failures.append(name)
        detail = traceback.format_exc().strip().splitlines()
        print(f"  FAIL  {name}\n        {detail[-1][:300]}\n        {detail[-3].strip()[:200]}", flush=True)
        keys = ["phase", "display", "focus", "input", "ghost", "menuMode", "menuItems", "inputHidden"]
        print(f"        state: { {k: harness.last_state.get(k) for k in keys} }"[:400], flush=True)

print(f"\n{len(tests) - len(failures)} of {len(tests)} passed in {time.time() - start:.1f}s")

if not pattern:
    ids = {f"{a.upper()}-{b}" for name in passed for a, b in re.findall(r"([a-z]{3})_(\d{3})", name)}
    path = os.path.join(os.path.dirname(HERE), "docs", "warp-parity.md")
    with open(path) as f:
        text = f.read()
    for item in ids:
        text = text.replace(f"- [ ] {item} ", f"- [x] {item} ")
    with open(path, "w") as f:
        f.write(text)
    print(f"parity: {text.count('- [x] ')} of {text.count('- [x] ') + text.count('- [ ] ')} verified")

sys.exit(1 if failures or not tests else 0)
