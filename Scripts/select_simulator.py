#!/usr/bin/env python3
"""Print an available iPhone UDID, preferring the newest installed iOS runtime."""
import json
import re
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
candidates = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.split(".iOS-")[-1]))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    raise SystemExit("No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components.")
print(max(candidates)[2])
