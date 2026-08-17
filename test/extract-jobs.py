#!/usr/bin/env python3
"""Print one `name<TAB>base64(run)` line per job in a `lefthook dump --format json`.

The `run` string is base64-encoded because a rule's command is multi-line and the
caller reads these back one job per line.
"""

import base64
import json
import sys

# Python writes \r\n on Windows. The caller reads these lines with `read` and
# feeds the second field to `base64 -d`, which rejects a stray \r as invalid
# input, so the translation has to be off.
sys.stdout.reconfigure(newline="\n")

config = json.load(sys.stdin)

for hook, body in config.items():
    if not isinstance(body, dict):
        continue
    for job in body.get("jobs", []):
        command = job.get("run")
        if not command:
            continue
        name = job.get("name", "?")
        encoded = base64.b64encode(command.encode()).decode()
        print(f"{name}\t{encoded}")
