#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns.

The mark is the app's own readout: three vertical ticks off the patch row, clay for Claude, cyan for
Codex, and one switched off between them. Two agents, something carried, something not — which is the
whole product in three strokes.

Three decisions worth keeping:

* **Vertical, not horizontal.** Two or three horizontal bars read as a hamburger menu at 16pt.
  Vertical ones read as a level meter, which is much closer to what this is.
* **Flat.** The earlier mark had a gradient plate, a specular ramp and a top-lit rim. The interface
  it belongs to has none of those: solid near-black, hairlines of one weight, no gloss. An icon that
  is glassier than its own window looks borrowed.
* **The plate stays a superellipse.** That is platform correctness rather than style — a plain
  rounded rectangle reads subtly wrong beside system icons.

Three ticks is the most that survives 16pt. Five turn to mush; two lose the "something is off" half
of the idea. Drawn supersampled and downsampled so the superellipse edge stays clean.
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw

SUP = 8                      # supersample factor
CANVAS = 1024                # final canvas
PLATE_RATIO = 824 / 1024     # macOS icons sit on an 824/1024 plate

PLATE = (0x0E, 0x10, 0x13)   # --surface
RIM = (0x2E, 0x33, 0x3A)     # --hairline-lit
OFF = (0x2E, 0x33, 0x3A)     # a tick that is not being paid for
CLAUDE = (0xE0, 0x85, 0x5C)  # --claude
CODEX = (0x6F, 0xD5, 0xE1)   # --codex

TICKS = (CLAUDE, OFF, CODEX)
SIDE = 0.175                 # margin either side of the row, as a fraction of the plate
GAP = 0.50                   # gap as a fraction of one cell — wide, like the patch row
HEIGHT = 0.60                # tick height as a fraction of the plate
RIM_WEIGHT = 0.009


def superellipse(box, n=5.0, steps=1536):
    """Apple-style squircle."""
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    a, b = (x1 - x0) / 2, (y1 - y0) / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append((cx + a * math.copysign(abs(ct) ** (2 / n), ct),
                    cy + b * math.copysign(abs(st) ** (2 / n), st)))
    return pts


def build(size=CANVAS):
    s = size * SUP
    plate = s * PLATE_RATIO
    margin = (s - plate) / 2
    box = (margin, margin, margin + plate, margin + plate)

    icon = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon(superellipse(box), fill=255)
    icon.paste(Image.new("RGBA", (s, s), PLATE + (255,)), (0, 0), mask)

    # One hairline, the same weight all the way round. The interface does not light its borders from
    # above, so neither does this.
    rim = Image.new("L", (s, s), 0)
    ImageDraw.Draw(rim).polygon(
        superellipse(box), outline=255, width=max(1, int(plate * RIM_WEIGHT)))
    icon.paste(Image.new("RGBA", (s, s), RIM + (255,)), (0, 0), rim)

    draw = ImageDraw.Draw(icon)
    inner = plate * (1 - 2 * SIDE)
    gap = inner / len(TICKS) * GAP
    width = (inner - gap * (len(TICKS) - 1)) / len(TICKS)
    height = plate * HEIGHT
    x = margin + plate * SIDE
    y = margin + (plate - height) / 2
    for colour in TICKS:
        draw.rectangle((x, y, x + width, y + height), fill=colour + (255,))
        x += width + gap

    return icon.resize((size, size), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build().save(os.path.join(root, "Resources", "AppIcon-preview.png"))

    iconset = os.path.join(root, "Resources", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            # Re-rendered at each size rather than downsampled from 1024: at 16pt a resampled
            # hairline turns to grey mud and the ticks lose their edges.
            build(px).save(os.path.join(iconset, name))

    subprocess.run(["iconutil", "-c", "icns", iconset,
                    "-o", os.path.join(root, "Resources", "AppIcon.icns")], check=True)
    print("wrote Resources/AppIcon.icns")


if __name__ == "__main__":
    sys.exit(main())
