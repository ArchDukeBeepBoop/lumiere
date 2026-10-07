#!/usr/bin/env python3
"""Draws Lumiere's app icon and builds Resources/Lumiere.icns.

    ./Scripts/make-icon.py

This script is the source of truth for the mark — it is a handful of geometric
primitives, so a change to the icon is a readable diff rather than an opaque blob.
The .icns it produces is committed too, so that bundling never depends on Pillow
being installed; regenerate it here rather than editing it.

There is no asset catalog because there is no Xcode on this machine. `iconutil`
takes a .iconset directory of exact sizes, which is what this writes.

The mark: a projector throwing a cone of light. Lumiere is light, the app is a
video player, and a cone reads as both. Deliberately only two shapes — at 16 pt an
icon is about twenty pixels across, and anything finer turns to mud. Colours come
from the same tokens as the app: ink #0D0F12 with the warm gold #C9A227.
"""
import math
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Rendered large and downsampled, which antialiases every edge for free.
CANVAS = 2048
# macOS 11+ proportions: the squircle covers ~80% of the canvas, leaving the
# margin the system expects rather than bleeding to the edge.
INSET = int(CANVAS * 0.098)
RADIUS = int((CANVAS - 2 * INSET) * 0.224)

INK_TOP = (26, 31, 38)
INK_BOTTOM = (13, 15, 18)
GOLD = (201, 162, 39)
GOLD_BRIGHT = (240, 214, 130)


def rounded_mask(size, inset, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - inset, size - inset], radius=radius, fill=255
    )
    return mask


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        gradient.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return gradient.resize((size, size), Image.NEAREST)


def draw_cone(size, apex, start_deg, end_deg, length):
    """The light cone, fading along its length so it reads as a beam rather than
    a solid wedge. The fade is a mask multiply, not per-polygon alpha, so the
    edges stay clean when downsampled."""
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)

    points = [apex]
    steps = 48
    for i in range(steps + 1):
        angle = math.radians(start_deg + (end_deg - start_deg) * i / steps)
        points.append((
            apex[0] + math.cos(angle) * length,
            apex[1] + math.sin(angle) * length,
        ))
    draw.polygon(points, fill=255)

    # Fade with distance from the apex.
    fade = Image.new("L", (size, size), 0)
    pixels = fade.load()
    for y in range(0, size, 2):
        for x in range(0, size, 2):
            # Clamped before the exponent: a negative base with a fractional
            # power is a complex number in Python, not a clipped zero.
            d = min(1.0, math.hypot(x - apex[0], y - apex[1]) / length)
            value = max(0, min(255, int(255 * (1.0 - d) ** 0.85)))
            pixels[x, y] = value
            if x + 1 < size:
                pixels[x + 1, y] = value
            if y + 1 < size:
                pixels[x, y + 1] = value
                if x + 1 < size:
                    pixels[x + 1, y + 1] = value

    return Image.composite(fade, Image.new("L", (size, size), 0), layer)


def render():
    size = CANVAS
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    body = vertical_gradient(size, INK_TOP, INK_BOTTOM).convert("RGBA")
    icon.paste(body, (0, 0), rounded_mask(size, INSET, RADIUS))

    # Vertically centred and symmetric about the horizontal axis. The first
    # attempt put the lamp up in a corner with a narrow diagonal beam, and it read
    # as a moon with a smudge — off-centre looked accidental rather than composed.
    apex = (size * 0.265, size * 0.5)
    lamp_r = size * 0.062
    beam_len = size * 0.60

    # Cone first, so the lamp sits on top of its own light.
    cone = draw_cone(size, apex, -27, 27, beam_len)
    cone = cone.filter(ImageFilter.GaussianBlur(size * 0.006))
    gold_layer = Image.new("RGBA", (size, size), GOLD + (255,))
    # Clipped to the squircle: a beam running past the corner would look like a
    # rendering mistake rather than a design.
    cone = Image.composite(cone, Image.new("L", (size, size), 0),
                           rounded_mask(size, INSET, RADIUS))
    icon = Image.alpha_composite(icon, Image.composite(
        gold_layer, Image.new("RGBA", (size, size), (0, 0, 0, 0)), cone
    ))

    # A glow, so the lamp looks like a source rather than a sticker.
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse(
        [apex[0] - lamp_r * 1.9, apex[1] - lamp_r * 1.9,
         apex[0] + lamp_r * 1.9, apex[1] + lamp_r * 1.9], fill=150
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.018))
    glow = Image.composite(glow, Image.new("L", (size, size), 0),
                           rounded_mask(size, INSET, RADIUS))
    icon = Image.alpha_composite(icon, Image.composite(
        Image.new("RGBA", (size, size), GOLD + (255,)),
        Image.new("RGBA", (size, size), (0, 0, 0, 0)), glow
    ))

    draw = ImageDraw.Draw(icon)
    draw.ellipse([apex[0] - lamp_r, apex[1] - lamp_r,
                  apex[0] + lamp_r, apex[1] + lamp_r], fill=GOLD_BRIGHT + (255,))
    return icon


def main():
    icon = render()
    iconset = os.path.join(ROOT, "build", "Lumiere.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset, exist_ok=True)

    # Exactly the names iconutil expects; anything else is silently ignored and
    # you get an .icns missing that size.
    for base in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = base * scale
            suffix = "" if scale == 1 else "@2x"
            icon.resize((px, px), Image.LANCZOS).save(
                os.path.join(iconset, f"icon_{base}x{base}{suffix}.png")
            )

    out = os.path.join(ROOT, "Resources", "Lumiere.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    print(f"    wrote {out} ({os.path.getsize(out) // 1024} KB)")

    preview = os.path.join(ROOT, "build", "icon-preview.png")
    icon.resize((512, 512), Image.LANCZOS).save(preview)
    print(f"    preview at {preview}")


if __name__ == "__main__":
    sys.exit(main())
