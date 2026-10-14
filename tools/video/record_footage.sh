#!/bin/bash
# Records raw gameplay (with game audio) for the marketing videos into
# build/footage/:
#   p-clean-NN.mp4   portrait 1080x1920 autopilot run of every mission (Shorts)
#   p-fail-NN.mp4    portrait reckless runs where the box gets caught
#   l-clean-NN.mp4   landscape 1920x1080 autopilot runs (trailer)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
out=build/footage
mkdir -p "$out"

# Movie Maker records at the project's window size and ignores --resolution,
# so each recording writes a temporary override.cfg (Godot reads it at startup
# and it overrides project.godot) with the exact layout and window size.
trap 'rm -f override.cfg' EXIT
window() {  # layout-w layout-h window-w window-h
	printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$@" > override.cfg
}

record() {  # name resolution level extra-flags...
	local name=$1 res=$2 level=$3; shift 3
	if [ "$res" = 1080x1920 ]; then window 648 1152 1080 1920; else window 1152 648 1920 1080; fi
	"$GODOT" --path . --write-movie "$out/$name.avi" --fixed-fps 30 \
		-- --level="$level" --autopilot --exit-on-end --no-music "$@" | grep RESULT | sed "s/^/$name: /" || true
	rm -f override.cfg
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 \
		-pix_fmt yuv420p -c:a aac -b:a 192k "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
}

for n in $(seq 1 10); do
	id=$(printf %02d "$n")
	record "p-clean-$id" 1080x1920 $((n - 1)) --portrait --timeout=120
	record "l-clean-$id" 1920x1080 $((n - 1)) --timeout=120
done
for n in 1 3 5 6 7; do
	record "p-fail-$(printf %02d "$n")" 1080x1920 $((n - 1)) --portrait --reckless --timeout=9
done
