#!/bin/bash
# Done when: the autopilot beats every mission without raising an alert.
# Proves each level is winnable. Runs headless and faster than real time.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
count=$(grep -c '"name": "VR-' scripts/levels.gd)
fail=0
for ((i = 0; i < count; i++)); do
	line=$("$GODOT" --headless --path . --fixed-fps 60 -- --level=$i --autopilot --exit-on-end --timeout=240 2>&1 | grep RESULT || true)
	echo "${line:-RESULT level=$((i + 1)) crashed}"
	[[ "$line" == *"complete"*"alerts=0"* ]] || fail=1
done
[ $fail -eq 0 ] && echo "autoplay: every mission beaten" || { echo "autoplay: some missions failed"; exit 1; }
