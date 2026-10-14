#!/bin/bash
# Records the autopilot beating missions, using Godot's Movie Maker mode
# (--write-movie renders every frame at a fixed rate, so the video is smooth
# no matter how fast the machine is), then encodes with ffmpeg:
#   docs/media/demo.gif                 hero GIF: the Final Exam at 2x speed
#   docs/media/missions/vr-NN.gif       one small GIF per mission
#   build/demos/full-playthrough.mp4    every mission back to back (release asset)
# Usage: bash tools/record_demos.sh [mission numbers, 1-based; default all]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)"; exit 1; }

count=$(grep -c '"name": "VR-' scripts/levels.gd)
missions=("$@")
[ ${#missions[@]} -gt 0 ] || missions=($(seq 1 "$count"))
raw=build/demos
mkdir -p "$raw" docs/media/missions

for n in "${missions[@]}"; do
	id=$(printf "%02d" "$n")
	echo "recording VR-$id..."
	"$GODOT" --path . --write-movie "$raw/vr-$id.avi" --fixed-fps 30 --resolution 1152x648 \
		-- --level=$((n - 1)) --autopilot --exit-on-end --timeout=120 | grep RESULT || true
	ffmpeg -loglevel error -y -i "$raw/vr-$id.avi" -c:v libx264 -preset slow -crf 24 \
		-pix_fmt yuv420p -movflags +faststart "$raw/vr-$id.mp4"
	# Small per-mission GIF: 2x speed, 640px wide, 12 fps, palette tuned per clip.
	ffmpeg -loglevel error -y -i "$raw/vr-$id.avi" -vf \
		"setpts=0.5*PTS,fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none" \
		"docs/media/missions/vr-$id.gif"
	rm "$raw/vr-$id.avi"
done

if [ -f "$raw/vr-10.mp4" ]; then
	echo "hero gif..."
	ffmpeg -loglevel error -y -i "$raw/vr-10.mp4" -vf \
		"setpts=0.5*PTS,fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
		docs/media/demo.gif
fi

if ls "$raw"/vr-*.mp4 >/dev/null 2>&1 && [ "$(ls "$raw"/vr-*.mp4 | wc -l)" -eq "$count" ]; then
	echo "full playthrough..."
	ls "$raw"/vr-*.mp4 | sed "s|^$raw/|file '|; s|$|'|" > "$raw/list.txt"
	ffmpeg -loglevel error -y -f concat -safe 0 -i "$raw/list.txt" -c copy "$raw/full-playthrough.mp4"
fi
ls -la docs/media docs/media/missions "$raw"
