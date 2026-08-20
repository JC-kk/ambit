#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns.

The mark is the product in one glyph: two independent switches, clay for Claude and blue for Codex,
one on and one off. They run vertically on purpose — two horizontal bars read as a hamburger menu at
16pt, two vertical pills do not. Drawn at 4x and downsampled so the superellipse edge stays clean.
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4096                     # supersampled canvas
CANVAS = 1024                # final canvas
PLATE = int(S * 824 / 1024)  # macOS icons sit on an 824/1024 plate
MARGIN = (S - PLATE) // 2

CLAY = (217, 120, 87)
BLUE = (92, 148, 250)
TRACK = (63, 66, 74)
KNOB = (247, 246, 244)


def superellipse(box, n=5.0, steps=1536):
    """Apple-style squircle. A plain rounded rectangle reads subtly wrong beside system icons."""
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


def vertical_gradient(size, stops):
    """stops: [(position 0-1, (r,g,b)), ...] ascending."""
    grad = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        lo = max(i for i, (p, _) in enumerate(stops) if p <= t) if t >= stops[0][0] else 0
        hi = min(lo + 1, len(stops) - 1)
        p0, c0 = stops[lo]
        p1, c1 = stops[hi]
        k = 0 if p1 == p0 else (t - p0) / (p1 - p0)
        grad.putpixel((0, y), tuple(round(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)))
    return grad.resize(size, Image.BILINEAR)


def build():
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    plate_box = (MARGIN, MARGIN, MARGIN + PLATE, MARGIN + PLATE)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(superellipse(plate_box), fill=255)

    plate = vertical_gradient((S, S), [
        (0.00, (54, 58, 66)),
        (0.45, (33, 35, 41)),
        (1.00, (19, 20, 24)),
    ]).convert("RGBA")
    icon.paste(plate, (0, 0), mask)

    # Specular falloff: a smooth top-down ramp, not a blurred ellipse. The ellipse left a visible
    # seam across the middle of the plate.
    sheen = Image.new("L", (1, S), 0)
    for y in range(S):
        t = (y - MARGIN) / PLATE
        v = 0.0 if t < 0 else max(0.0, 1.0 - (t / 0.5) ** 1.4)
        sheen.putpixel((0, y), int(46 * v))
    sheen = sheen.resize((S, S), Image.BILINEAR)
    sheen.paste(0, (0, 0), Image.eval(mask, lambda v: 255 - v))
    icon.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), sheen)

    # Hairline rim along the top of the plate, the way glass catches an edge.
    rim = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(rim)
    rd.polygon(superellipse(plate_box), outline=90, width=int(PLATE * 0.006))
    rd.rectangle((0, MARGIN + PLATE * 0.42, S, S), fill=0)
    rim = rim.filter(ImageFilter.GaussianBlur(PLATE * 0.002))
    icon.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), rim)

    draw = ImageDraw.Draw(icon)

    track_w = int(PLATE * 0.245)
    track_h = int(PLATE * 0.515)
    radius = track_w // 2
    gap = int(PLATE * 0.105)
    total_w = track_w * 2 + gap
    x0 = MARGIN + (PLATE - total_w) // 2
    y0 = MARGIN + (PLATE - track_h) // 2
    knob_r = int(track_w * 0.325)
    inset = radius

    # Claude: on. Filled clay, knob at the top.
    box = (x0, y0, x0 + track_w, y0 + track_h)
    draw.rounded_rectangle(box, radius=radius, fill=CLAY + (255,))
    cx, cy = x0 + radius, y0 + inset
    draw.ellipse((cx - knob_r, cy - knob_r, cx + knob_r, cy + knob_r), fill=KNOB + (255,))

    # Codex: off. Neutral track, blue rim, knob at the bottom.
    bx = x0 + track_w + gap
    box = (bx, y0, bx + track_w, y0 + track_h)
    ring = int(PLATE * 0.021)
    draw.rounded_rectangle(box, radius=radius, fill=TRACK + (255,))
    draw.rounded_rectangle(box, radius=radius, outline=BLUE + (255,), width=ring)
    cx, cy = bx + radius, y0 + track_h - inset
    draw.ellipse((cx - knob_r, cy - knob_r, cx + knob_r, cy + knob_r), fill=BLUE + (255,))

    return icon.resize((CANVAS, CANVAS), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon = build()
    icon.save(os.path.join(root, "Resources", "AppIcon-preview.png"))

    iconset = os.path.join(root, "Resources", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))

    subprocess.run(["iconutil", "-c", "icns", iconset,
                    "-o", os.path.join(root, "Resources", "AppIcon.icns")], check=True)
    print("wrote Resources/AppIcon.icns")


if __name__ == "__main__":
    sys.exit(main())
