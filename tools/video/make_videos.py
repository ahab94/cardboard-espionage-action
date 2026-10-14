#!/usr/bin/env python3
"""Builds the marketing videos from recorded footage.

    bash tools/video/record_footage.sh      # once: raw gameplay -> build/footage/
    /usr/bin/python3 tools/video/make_videos.py [video-id ...]

Needs Pillow (captions) and ffmpeg. Writes build/videos/<id>.mp4 plus
docs/marketing/youtube.md (titles, descriptions, tags for uploading).

Each video is a list of segments cut from the footage (optionally sped up),
with captions burned on top. Audio = the footage's game sound effects + a
playful music bed + comedy stingers (tools/video/make_video_audio.py).
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOOTAGE = os.path.join(ROOT, "build", "footage")
OUT = os.path.join(ROOT, "build", "videos")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
VIDEO_AUDIO = os.path.join(ROOT, "build", "video_audio")   # tools/video/make_video_audio.py


def sfx_path(name):
    """Comedy effects (build/video_audio) first, then the game's own (audio/sfx)."""
    for folder in (VIDEO_AUDIO, os.path.join(ROOT, "audio", "sfx")):
        path = os.path.join(folder, name + ".wav")
        if os.path.exists(path):
            return path
    raise FileNotFoundError(name)

PLAY = "https://ahab94.github.io/cardboard-espionage-action/"
PLAY_SHORT = "ahab94.github.io/cardboard-espionage-action"   # shown on screen
REPO = "https://github.com/ahab94/cardboard-espionage-action"
RELEASES = REPO + "/releases/latest"

CYAN = (70, 214, 255)
YELLOW = (255, 216, 74)
GREEN = (77, 255, 154)
RED = (255, 51, 68)
NAVY = (11, 42, 64)
INK = (3, 10, 18)

LINKS = f"""⭐ Open source on GitHub, a star helps a lot: {REPO}
⬇ Windows / Mac / Linux downloads: {RELEASES}"""


def description(blurb, tags):
    return f"""▶ PLAY FREE in your browser: {PLAY}

{blurb}

{LINKS}

Cardboard Espionage Action is a free, family-friendly stealth game where you play as a cardboard box. Sneak past cameras, guards, drones and lasers across 10 missions. Made with the Godot engine; every sound and pixel is made in code.

{" ".join("#" + t for t in tags)}"""


BASE_TAGS = ["cardboard espionage action", "indie game", "stealth game", "free game",
             "browser game", "godot", "gamedev", "cardboard box", "family friendly game"]

# --- The ten videos ------------------------------------------------------------
# Times are in seconds. Segment times refer to the source clip; caption and
# sfx times refer to the finished video.

VIDEOS = [
    {
        "id": "01-trailer", "orient": "landscape",
        "segments": [
            ("l-clean-02", 1.6, 5.4, 1.0), ("l-clean-05", 1.0, 6.0, 1.3), ("l-clean-06", 2.5, 7.5, 1.3),
            ("l-clean-04", 9.0, 15.5, 1.5), ("l-clean-08", 3.0, 9.0, 1.3), ("l-clean-07", 14.5, 19.0, 1.0),
            ("l-clean-10", 10.0, 22.0, 1.6),
        ],
        "intro": ("YOU ARE A\nCARDBOARD BOX.", 3.0),
        "captions": [
            (0.2, 3.6, "Hold still...\nit's just a box.", "low"),
            (4.0, 7.6, "Sneak past guards", "low"),
            (7.7, 11.4, "Dodge the drones", "low"),
            (11.5, 15.7, "Time the lasers", "low"),
            (15.8, 20.3, "Stay behind the turret", "low"),
            (20.4, 24.8, "Grab the keycard", "low"),
            (24.9, 32.3, "10 missions.\nEverything at once.", "low"),
        ],
        "sfx": [(-2.7, "pop"), (-0.5, "slide_up"), (0.8, "uh_oh", 0.8), (21.2, "ding")],
        "cut_whoosh": True, "caption_pop": False,
        "outro": 4.5,
        "title": "Cardboard Espionage Action: you are a cardboard box (free stealth game trailer)",
        "blurb": "You are a cardboard box. Hold still when the cameras look your way!",
        "tags": BASE_TAGS + ["game trailer", "indie game trailer"],
    },
    {
        "id": "01b-trailer-short", "orient": "portrait",
        "segments": [
            ("p-clean-02", 1.6, 5.4, 1.0), ("p-clean-05", 1.0, 6.0, 1.3), ("p-clean-06", 2.5, 7.5, 1.3),
            ("p-clean-04", 9.0, 15.5, 1.5), ("p-clean-08", 3.0, 9.0, 1.3), ("p-clean-07", 14.5, 19.0, 1.0),
            ("p-clean-10", 10.0, 22.0, 1.6),
        ],
        "intro": ("YOU ARE A\nCARDBOARD\nBOX.", 2.2),
        "captions": [
            (0.2, 3.6, "Hold still...\nit's just a box.", "hook"),
            (4.0, 7.6, "Sneak past guards", "hook"),
            (7.7, 11.4, "Dodge the drones", "hook"),
            (11.5, 15.7, "Time the lasers", "hook"),
            (15.8, 20.3, "Stay behind the turret", "hook"),
            (20.4, 24.8, "Grab the keycard", "hook"),
            (24.9, 32.3, "10 missions.\nEverything at once.", "hook"),
        ],
        "sfx": [(-2.0, "pop"), (-0.4, "slide_up"), (0.8, "uh_oh", 0.8), (21.2, "ding")],
        "cut_whoosh": True,
        "outro": 3.5,
        "title": "You are a cardboard box. Don't get caught. 📦 #shorts",
        "blurb": "A free stealth game where you play as a cardboard box. 10 missions, all in your browser.",
        "tags": BASE_TAGS + ["shorts", "game trailer"],
    },
    {
        "id": "02-i-made-a-game", "orient": "portrait",
        "segments": [
            ("p-clean-01", 0.0, 4.0, 1.4), ("p-clean-02", 1.8, 4.6, 1.0), ("p-clean-05", 2.0, 6.5, 1.5),
            ("p-clean-06", 2.5, 7.0, 1.5), ("p-clean-04", 10.0, 16.0, 2.0), ("p-clean-10", 25.0, 31.4, 1.3),
        ],
        "captions": [
            (0.0, 2.9, "I made a game where\nyou're a\nCARDBOARD BOX", "hook"),
            (2.9, 5.7, "Cameras can't see you\nif you hold still*", "hook"),
            (4.6, 5.7, "*mostly", "note"),
            (5.7, 8.7, "Guards walk around...", "hook"),
            (8.7, 11.7, "Drones see over walls", "hook"),
            (11.7, 14.7, "Lasers. So many lasers.", "hook"),
            (14.7, 19.6, "And it's FREE to play\nin your browser!", "hook"),
        ],
        "sfx": [(4.6, "boing", 0.8), (11.7, "bonk"), (14.7, "slide_up"), (18.5, "ding")],
        "cut_whoosh": True,
        "title": "I made a game where you're a CARDBOARD BOX 📦 #shorts",
        "blurb": "I made a stealth game where you play as a cardboard box. Should I add more levels?",
        "tags": BASE_TAGS + ["shorts", "i made a game", "devlog", "game dev"],
    },
    {
        "id": "03-hold-still", "orient": "portrait",
        "segments": [("p-clean-02", 0.6, 6.5, 1.0), ("p-clean-02", 8.2, 12.0, 1.0)],
        "sfx": [(1.6, "uh_oh"), (4.0, "boing", 0.8), (5.8, "slide_down", 0.7), (9.2, "ding")],
        "captions": [
            (0.0, 1.9, "When the camera\nlooks your way...", "hook"),
            (1.9, 4.0, "HOLD STILL.", "big"),
            (4.0, 5.9, "it's just a box.", "hook"),
            (5.9, 9.7, "every. single. time.", "hook"),
        ],
        "title": "Hold still... it's just a box 📦 #shorts",
        "blurb": "The secret to stealth: be a box. Hold still and the camera can barely tell!",
        "tags": BASE_TAGS + ["shorts", "stealth", "funny game"],
    },
    {
        "id": "04-wait-for-it", "orient": "portrait",
        "segments": [("p-fail-01", 0.0, 4.6, 1.0), ("p-fail-03", 1.6, 5.0, 1.0), ("p-fail-07", 2.0, 5.4, 1.0)],
        "sfx": [(3.25, "record_scratch"), (6.45, "bonk"), (9.82, "record_scratch"), (10.3, "sad_trombone")],
        "captions": [
            (0.0, 2.9, "Me trying to sneak:", "hook"),
            (2.9, 4.6, "wait for it...", "hook"),
            (4.6, 6.6, "attempt #2", "hook"),
            (8.0, 9.8, "attempt #47", "hook"),
            (10.2, 11.4, "...help", "hook"),
        ],
        "outro": 2.5,
        "title": "Me trying to sneak in a cardboard box 😅 #shorts",
        "blurb": "Stealth is hard when you're a cardboard box. Can you do better? Play free below!",
        "tags": BASE_TAGS + ["shorts", "fail", "funny", "gaming fails"],
    },
    {
        "id": "05-lasers", "orient": "portrait",
        "segments": [("p-clean-04", 0.0, 33.3, 1.6)],
        "sfx": [(7.0, "slide_up"), (20.6, "ding")],
        "captions": [
            (0.0, 3.0, "Can YOU get past\nthe lasers?", "hook"),
            (3.0, 7.0, "Wait for the flicker...", "hook"),
            (7.0, 9.0, "NOW!", "big"),
            (16.5, 20.8, "Comment your best time!", "hook"),
        ],
        "title": "Can YOU get past the lasers? ⚡ #shorts",
        "blurb": "Lasers flicker right before they switch on. Time it right! Comment your best time.",
        "tags": BASE_TAGS + ["shorts", "lasers", "challenge", "can you beat this"],
    },
    {
        "id": "06-drones", "orient": "portrait",
        "segments": [("p-clean-06", 0.0, 9.3, 1.0)],
        "sfx": [(0.3, "uh_oh", 0.7), (3.2, "slide_down", 0.7), (6.6, "ding")],
        "captions": [
            (0.0, 3.2, "Drones can see\nOVER walls", "hook"),
            (3.2, 6.6, "Stay out of\nthe spotlight!", "hook"),
            (6.6, 9.3, "Safe! 😎", "hook"),
        ],
        "title": "Drones can see over walls?! 😳 #shorts",
        "blurb": "Walls won't hide you from a drone. Stay out of the spotlight!",
        "tags": BASE_TAGS + ["shorts", "drone", "stealth"],
    },
    {
        "id": "07-guard", "orient": "portrait",
        "segments": [("p-clean-05", 0.0, 9.3, 1.0)],
        "sfx": [(3.0, "tiptoe"), (4.3, "tiptoe"), (5.6, "tiptoe"), (6.3, "ding")],
        "captions": [
            (0.0, 3.0, "POV: the guard is\nRIGHT there", "hook"),
            (3.0, 6.3, "don't move...\ndon't move...", "hook"),
            (6.3, 9.3, "made it!", "hook"),
        ],
        "title": "POV: the guard is RIGHT there 👀 #shorts",
        "blurb": "Guards walk set routes and look around. Never bump into one!",
        "tags": BASE_TAGS + ["shorts", "pov", "stealth"],
    },
    {
        "id": "08-turret", "orient": "portrait",
        "segments": [("p-clean-08", 0.0, 15.1, 1.25)],
        "sfx": [(3.2, "whoosh", 0.6), (7.5, "tiptoe"), (8.8, "tiptoe"), (11.9, "ding")],
        "captions": [
            (0.0, 3.2, "NEVER stand in front\nof the turret", "hook"),
            (3.2, 7.5, "It never stops spinning...", "hook"),
            (7.5, 12.1, "...so move behind its back", "hook"),
        ],
        "title": "Never stand in front of the turret 🔄 #shorts",
        "blurb": "The turret spins forever. The trick: move when it's looking away!",
        "tags": BASE_TAGS + ["shorts", "turret", "stealth"],
    },
    {
        "id": "09-speedrun", "orient": "portrait",
        "segments": [(f"p-clean-{n:02d}", end - 4.2, end, 1.6) for n, end in
                     [(1, 9.2), (2, 19.4), (3, 15.8), (4, 33.2), (5, 9.2), (6, 9.2),
                      (7, 24.7), (8, 15.0), (9, 28.1), (10, 31.4)]],
        "cut_whoosh": True,
        "captions": [(0.0, 2.6, "ALL 10 LEVELS\nin 30 seconds", "hook")] +
                    [(i * 2.625, (i + 1) * 2.625, f"{i + 1}/10", "counter") for i in range(10)],
        "sfx": [(26.0, "complete")],
        "title": "All 10 levels in 30 seconds ⏱️ #shorts",
        "blurb": "Every mission, back to back. How fast can you beat it? Play free below!",
        "tags": BASE_TAGS + ["shorts", "speedrun", "satisfying"],
    },
    {
        "id": "10-final-level", "orient": "portrait",
        "segments": [("p-clean-10", 0.0, 31.5, 1.5)],
        "sfx": [(6.5, "uh_oh"), (12.0, "slide_up"), (20.6, "ding")],
        "captions": [
            (0.0, 3.0, "The final level\nhas EVERYTHING", "hook"),
            (3.0, 6.5, "cameras. turret. drone.", "hook"),
            (6.5, 9.5, "hide... HIDE!", "hook"),
            (12.0, 14.5, "got the keycard!", "hook"),
            (15.0, 19.0, "now the vault...", "hook"),
        ],
        "title": "The final level has EVERYTHING 😱 #shorts",
        "blurb": "Cameras, a turret, a drone, a guard, lasers and a locked vault. All at once.",
        "tags": BASE_TAGS + ["shorts", "final level", "boss level"],
    },
]


# --- Graphics ------------------------------------------------------------------

def frame_size(orient):
    return (1080, 1920) if orient == "portrait" else (1920, 1080)


def font(size):
    return ImageFont.truetype(FONT, size)


def draw_centered(draw, lines, y_center, size, fill, width, stroke=10, line_gap=1.12):
    f = font(size)
    heights = [size * line_gap] * len(lines)
    y = y_center - sum(heights) / 2
    for line, h in zip(lines, heights):
        w = draw.textlength(line, font=f)
        draw.text(((width - w) / 2, y), line, font=f, fill=fill, stroke_width=stroke, stroke_fill=INK)
        y += h


def caption_png(path, text, style, orient):
    """Full-frame transparent PNG with the caption placed for the format."""
    W, H = frame_size(orient)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split("\n") if text else []
    portrait = orient == "portrait"
    if not lines:
        img.save(path)
        return
    if style == "big":
        draw_centered(d, lines, H * (0.29 if portrait else 0.5), 150 if portrait else 140, YELLOW, W, stroke=14)
    elif style == "note":
        draw_centered(d, lines, H * 0.39, 48, (200, 220, 230), W, stroke=6)
    elif style == "counter":
        draw_centered(d, lines, H * 0.84, 110, GREEN, W, stroke=12)
    elif style == "cta":   # call to action with the play link, above the Shorts UI
        cy = H * (0.66 if portrait else 0.78)
        f1, f2 = font(52 if portrait else 60), font(36 if portrait else 38)
        l1, l2 = "PLAY FREE IN YOUR BROWSER", PLAY_SHORT
        w = max(d.textlength(l1, font=f1), d.textlength(l2, font=f2)) + 140
        w = min(w, W - 60)
        h = 190 if portrait else 175
        d.rounded_rectangle([(W - w) / 2, cy - h / 2, (W + w) / 2, cy + h / 2], 30, fill=(255, 216, 74, 245))
        # a drawn "play" triangle, since the font has no symbol for it
        tx = (W - d.textlength(l1, font=f1)) / 2 - 10
        d.polygon([(tx - 46, cy - 62), (tx - 46, cy - 18), (tx - 8, cy - 40)], fill=INK)
        d.text(((W - d.textlength(l1, font=f1)) / 2 + 12, cy - 75), l1, font=f1, fill=INK)
        d.text(((W - d.textlength(l2, font=f2)) / 2, cy + 18), l2, font=f2, fill=(20, 40, 60))
    elif style == "low":   # landscape lower-third
        size = 76
        f = font(size)
        widths = [d.textlength(l, font=f) for l in lines]
        box_w, box_h = max(widths) + 80, len(lines) * size * 1.15 + 40
        y0 = H - box_h - 120
        d.rounded_rectangle([(W - box_w) / 2, y0, (W + box_w) / 2, y0 + box_h], 28, fill=(3, 10, 18, 190))
        draw_centered(d, lines, y0 + box_h / 2, size, (255, 255, 255), W, stroke=0)
    else:  # hook: the top band of a Short, where the platform UI doesn't cover it
        size = 84 if max(len(l) for l in lines) <= 18 else 70
        f = font(size)
        widths = [d.textlength(l, font=f) for l in lines]
        box_w, box_h = min(W - 40, max(widths) + 70), len(lines) * size * 1.15 + 44
        cy = H * 0.215
        d.rounded_rectangle([(W - box_w) / 2, cy - box_h / 2, (W + box_w) / 2, cy + box_h / 2], 34,
                            fill=(255, 255, 255, 235))
        draw_centered(d, lines, cy, size, INK, W, stroke=0)
    img.save(path)


def draw_box(d, cx, cy, s):
    """The cardboard box hero, drawn like in the game."""
    d.rectangle([cx - s, cy - s, cx + s, cy + s], fill=(196, 154, 90), outline=(138, 101, 52), width=max(4, s // 12))
    d.rectangle([cx - s * 0.12, cy - s, cx + s * 0.12, cy + s], fill=(226, 197, 143))
    d.rectangle([cx - s * 0.62, cy - s * 0.3, cx + s * 0.62, cy + s * 0.08], fill=(20, 12, 6))
    for ex in (-0.28, 0.28):
        r = s * 0.12
        d.ellipse([cx + ex * s - r, cy - s * 0.11 - r, cx + ex * s + r, cy - s * 0.11 + r], fill="white")


def card_png(path, orient, title_lines, kind):
    W, H = frame_size(orient)
    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)
    step = 90
    for x in range(0, W, step):
        d.line([x, 0, x, H], fill=(28, 70, 96), width=2)
    for y in range(0, H, step):
        d.line([0, y, W, y], fill=(28, 70, 96), width=2)
    portrait = orient == "portrait"
    if kind == "intro":
        draw_box(d, W // 2, int(H * (0.36 if portrait else 0.33)), 120 if portrait else 110)
        draw_centered(d, title_lines, H * (0.6 if portrait else 0.7), 120 if portrait else 110, CYAN, W, stroke=12)
    else:  # outro: title + call to action
        draw_box(d, W // 2, int(H * (0.25 if portrait else 0.22)), 100 if portrait else 80)
        draw_centered(d, ["CARDBOARD", "ESPIONAGE ACTION"] if portrait else ["CARDBOARD ESPIONAGE ACTION"],
                      H * (0.42 if portrait else 0.44), 96 if portrait else 92, CYAN, W, stroke=10)
        draw_centered(d, ["PLAY FREE", "IN YOUR BROWSER"] if portrait else ["PLAY FREE IN YOUR BROWSER"],
                      H * (0.58 if portrait else 0.62), 84 if portrait else 78, YELLOW, W, stroke=10)
        draw_centered(d, [PLAY_SHORT], H * (0.69 if portrait else 0.75), 46 if portrait else 44, (255, 255, 255), W, stroke=6)
        draw_centered(d, ["free & open source on GitHub"],
                      H * (0.76 if portrait else 0.85), 44 if portrait else 40, (180, 210, 225), W, stroke=6)
    img.save(path)


def thumbnail_png(path):
    """Custom thumbnail for the landscape trailer (1280x720)."""
    W, H = 1280, 720
    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)
    for x in range(0, W, 64):
        d.line([x, 0, x, H], fill=(28, 70, 96), width=2)
    for y in range(0, H, 64):
        d.line([0, y, W, y], fill=(28, 70, 96), width=2)
    # A camera cone sweeping toward the box.
    d.polygon([(1180, 40), (520, 330), (760, 660)], fill=(110, 255, 180))
    d.polygon([(1180, 40), (560, 360), (740, 620)], fill=(150, 255, 200))
    d.rectangle([1150, 20, 1215, 70], fill=(29, 43, 54), outline=CYAN, width=5)
    draw_box(d, 360, 420, 150)
    f = font(150)
    d.text((W - d.textlength("?!", font=f) - 330, 150), "?!", font=f, fill=YELLOW, stroke_width=12, stroke_fill=INK)
    draw_centered(d, ["YOU ARE A BOX"], 95, 104, (255, 255, 255), W, stroke=12)
    img.save(path)


# --- Assembly --------------------------------------------------------------------

def run(cmd):
    subprocess.run(cmd, check=True)


def atempo_chain(speed):
    # atempo accepts 0.5..2.0 per stage, so chain stages for bigger changes.
    parts, s = [], speed
    while s > 2.0:
        parts.append("atempo=2.0")
        s /= 2.0
    parts.append(f"atempo={s:.4f}")
    return ",".join(parts)


def cut(src, start, end, speed, path, W, H, keep_audio):
    vf = f"setpts=PTS/{speed},scale={W}:{H},fps=30"
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-to", str(end),
           "-i", os.path.join(FOOTAGE, src + ".mp4"), "-vf", vf]
    if keep_audio:
        cmd += ["-af", atempo_chain(speed) + ",aresample=48000", "-c:a", "aac", "-b:a", "192k", "-ac", "2"]
    else:
        cmd += ["-an"]
    cmd += ["-c:v", "libx264", "-preset", "fast", "-crf", "16", "-pix_fmt", "yuv420p", path]
    run(cmd)


def still(png, seconds, path, keep_audio):
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-loop", "1", "-t", str(seconds), "-i", png]
    if keep_audio:
        cmd += ["-f", "lavfi", "-t", str(seconds), "-i", "anullsrc=r=48000:cl=stereo",
                "-c:a", "aac", "-b:a", "192k", "-shortest"]
    cmd += ["-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "16", path]
    run(cmd)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def build(v, tmp):
    W, H = frame_size(v["orient"])
    clip_audio = True   # always keep the footage's game sound effects
    parts = []
    if "intro" in v:
        text, secs = v["intro"]
        png = os.path.join(tmp, "intro.png")
        card_png(png, v["orient"], text.split("\n"), "intro")
        parts.append(os.path.join(tmp, "intro.mp4"))
        still(png, secs, parts[-1], clip_audio)
    for i, (src, a, b, speed) in enumerate(v["segments"]):
        parts.append(os.path.join(tmp, f"seg{i}.mp4"))
        cut(src, a, b, speed, parts[-1], W, H, clip_audio)
    if v.get("outro"):
        png = os.path.join(tmp, "outro.png")
        card_png(png, v["orient"], [], "outro")
        parts.append(os.path.join(tmp, "outro.mp4"))
        still(png, v["outro"], parts[-1], clip_audio)

    listing = os.path.join(tmp, "list.txt")
    with open(listing, "w") as f:
        f.writelines(f"file '{p}'\n" for p in parts)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
    total = duration(joined)
    offset = v["intro"][1] if "intro" in v else 0.0   # captions are timed from the first gameplay frame

    # Captions: one transparent full-frame PNG each, shown over its time window.
    # Every video ends with the play link on screen: links in Shorts
    # descriptions aren't clickable, so viewers need to see the address.
    gameplay_end = total - offset - (v.get("outro") or 0)
    captions = list(v["captions"])
    if not v.get("outro"):
        captions.append((max(0.0, gameplay_end - 3.0), gameplay_end, "cta", "cta"))
    inputs, filters, last = [], [], "[0:v]"
    for i, (t0, t1, text, style) in enumerate(captions):
        png = os.path.join(tmp, f"cap{i}.png")
        caption_png(png, text, style, v["orient"])
        # Loop the still image for the whole video: a single-frame input ends
        # immediately, so a caption that starts after an intro card would never show.
        inputs += ["-loop", "1", "-t", f"{total:.2f}", "-i", png]
        filters.append(f"{last}[{i + 1}:v]overlay=0:0:enable='between(t,{t0 + offset:.2f},{t1 + offset:.2f})'[v{i}]")
        last = f"[v{i}]"
    n_caps = len(captions)

    # Audio: the clip's game sound effects (footage is recorded without game
    # music), a playful music bed, comedy stingers from the spec, a soft pop
    # on every caption and a whoosh on every cut.
    cues = [(t + offset, name, vol) for t, name, vol in
            [(c[0], c[1], c[2] if len(c) > 2 else 1.0) for c in v.get("sfx", [])]]
    if v.get("caption_pop", True):
        cues += [(t0 + offset, "pop", 0.45) for t0, _, text, _ in v["captions"] if text]
    if v.get("cut_whoosh"):
        t = offset
        for _, a, b, speed in v["segments"][:-1]:
            t += (b - a) / speed
            cues.append((t - 0.15, "whoosh", 0.5))
    base = n_caps + 1
    audio_inputs = ["-stream_loop", "-1", "-i", os.path.join(VIDEO_AUDIO, v.get("music", "sneaky_theme") + ".wav")]
    mix = ["[0:a]volume=1.0[g]", f"[{base}:a]volume={v.get('music_volume', 0.5)}[m]"]
    labels = ["[g]", "[m]"]
    for j, (t, name, vol) in enumerate(cues):
        audio_inputs += ["-i", sfx_path(name)]
        ms = max(0, int(t * 1000))
        mix.append(f"[{base + 1 + j}:a]adelay={ms}|{ms},volume={vol * 1.2:.2f}[s{j}]")
        labels.append(f"[s{j}]")
    mix.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,atrim=0:{total:.2f},"
               f"loudnorm=I=-14:TP=-1.5:LRA=11,afade=t=in:d=0.2,afade=t=out:st={total - 0.8:.2f}:d=0.8,"
               f"aresample=48000[a]")
    audio_filter = ";".join(mix)

    graph = ";".join(filters + [audio_filter]) if filters else audio_filter
    vmap = last if filters else "0:v"
    out = os.path.join(OUT, v["id"] + ".mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", joined, *inputs, *audio_inputs,
         "-filter_complex", graph, "-map", vmap, "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30",
         "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", "-t", f"{total:.2f}", out])
    print(f"{v['id']}: {total:.1f}s -> {os.path.relpath(out, ROOT)}")
    return total


def write_metadata(lengths):
    path = os.path.join(ROOT, "docs", "marketing", "youtube.md")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = ["# YouTube uploads", "",
             "Generated by `tools/video/make_videos.py`. Audience: **No, it's not made for kids** (family-friendly, all ages).",
             "Upload as **Private** first, then publish after review.", ""]
    for v in VIDEOS:
        lines += [f"## {v['id']} ({'Short' if v['orient'] == 'portrait' else 'video'}, {lengths.get(v['id'], 0):.0f}s)", "",
                  f"**Title:** {v['title']}", "", "**Description:**", "", "```",
                  description(v["blurb"], ["CardboardEspionageAction", "indiegame", "gamedev", "godot", "stealth"]),
                  "```", "", f"**Tags:** {', '.join(v['tags'])}", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))
    with open(os.path.join(OUT, "metadata.json"), "w") as f:
        json.dump([{"id": v["id"], "file": v["id"] + ".mp4", "title": v["title"],
                    "description": description(v["blurb"], ["CardboardEspionageAction", "indiegame", "gamedev", "godot", "stealth"]),
                    "tags": v["tags"], "short": v["orient"] == "portrait"} for v in VIDEOS], f, indent=2)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    os.makedirs(OUT, exist_ok=True)
    wanted = set(sys.argv[1:])
    lengths = {}
    for v in VIDEOS:
        if wanted and v["id"] not in wanted and v["id"].split("-")[0] not in wanted:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            lengths[v["id"]] = build(v, tmp)
    thumbnail_png(os.path.join(OUT, "01-trailer-thumbnail.png"))
    if not wanted:
        write_metadata(lengths)


if __name__ == "__main__":
    main()
