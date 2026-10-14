#!/bin/bash
# Done when: Godot 4 is installed and runs from the terminal, and this
# project opens and runs its smoke test headless without errors.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || true)
[ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ] && GODOT=/Applications/Godot.app/Contents/MacOS/Godot
[ -n "$GODOT" ] || { echo "Godot is not installed"; exit 1; }
"$GODOT" --version | grep -E '^4\.' >/dev/null || { echo "Godot is not version 4"; exit 1; }
[ -f project.godot ] || { echo "No project.godot"; exit 1; }
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --path . --script res://tests/smoke_test.gd 2>&1) || { echo "$out"; exit 1; }
echo "$out" | grep -q "SMOKE OK" || { echo "$out"; echo "smoke test did not print SMOKE OK"; exit 1; }
echo "godot-sandbox: all good"
