"""Lumiere's surfaces: small seamless textures for the Quest's places.

Each is 512 x 512 and tiles without a seam (every noise is made periodic by
building it in the frequency domain). Most are grey: the place's own colour
for the part, lit by the house lights and the film, is multiplied over the
texture, so one wood serves oak floors and smoked beams alike and the light
code is unchanged. The books and the two pictures carry their own colours.

Deterministic (seeded): a rebuild is the same set.

    python3 android/Scripts/textures.py [OUT_DIR]
"""
import os
import sys
import numpy as np
from PIL import Image

N = 512
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "quest", "src", "main", "res", "drawable-nodpi")
rng = np.random.default_rng(2026)


def periodic_noise(beta=2.0, sx=1.0, sy=1.0, seed=None):
    """Seamless 1/f^beta noise, 0..1. [sx]/[sy] weight the frequencies: sx > sy makes streaks along x."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((N, N))
    fy = np.fft.fftfreq(N)[:, None] * sy
    fx = np.fft.fftfreq(N)[None, :] * sx
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / f ** (beta / 2)
    spectrum[0, 0] = 0
    n = np.real(np.fft.ifft2(spectrum))
    n -= n.min()
    return n / n.max()


def grain(stretch=40.0, rings=22, seed=0):
    """Wood grain running along x: fine fibres, and thin dark growth lines that bend only gently."""
    fibres = periodic_noise(1.1, stretch, 1.0, seed)
    warp = periodic_noise(3.4, 1.0, 1.0, seed + 1)
    y = np.arange(N)[:, None] / N
    lines = 0.5 + 0.5 * np.cos(2 * np.pi * (y * rings + (warp - 0.5) * 1.6))
    late = lines ** 8                       # the latewood: thin, darker bands
    tone = periodic_noise(3.0, 4.0, 1.0, seed + 2)
    return np.clip(0.55 + 0.25 * fibres + 0.2 * tone - 0.35 * late, 0, 1)


def save(name, a, colour=False):
    a = np.clip(a, 0, 1)
    if not colour:
        a = np.repeat(a[:, :, None], 3, axis=2)
    # A little noise before quantising: no banding in the dark.
    a = a + rng.uniform(-0.5, 0.5, a.shape) / 255
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    path = os.path.join(OUT, f"lumiere_tex_{name}.jpg")
    img.save(path, quality=85, optimize=True)
    print(f"{path}: {os.path.getsize(path) // 1024} KB")


def wood():
    """Plain timber: the cabin's walls, beams, fins, credenza and mantel; the pontoon's beams and posts."""
    return 0.6 + 0.4 * grain(seed=11)


def planks(boards=4, worn=False):
    """Floor boards across v, each its own cut of grain and shade, butt joints staggered, dark seams."""
    out = np.zeros((N, N))
    h = N // boards
    for b in range(boards):
        g = grain(rings=10, seed=100 + b * 7 + (50 if worn else 0))
        shift = rng.integers(0, N)
        g = np.roll(g, shift, axis=1)
        shade = rng.uniform(0.86, 1.0)
        out[b * h:(b + 1) * h] = shade * (0.7 + 0.3 * g[b * h:(b + 1) * h])
        out[b * h:b * h + 2] *= 0.45                       # the seam between boards
        joint = rng.integers(0, N)                          # a butt joint somewhere along it
        out[b * h:(b + 1) * h, joint:joint + 2] *= 0.55
    if worn:
        # Weathered: the grain opened into fine cracks, a few knots, the whole a little silvered.
        cracks = periodic_noise(1.2, 40, 1.0, 77)
        out *= np.where(cracks > 0.82, 0.6, 1.0)
        for _ in range(7):
            cx, cy = rng.integers(0, N, 2)
            yy, xx = np.ogrid[:N, :N]
            dx = (xx - cx + N // 2) % N - N // 2
            dy = (yy - cy + N // 2) % N - N // 2
            knot = np.exp(-((dx / 9.0) ** 2 + (dy / 4.0) ** 2))
            out *= 1 - 0.45 * knot
        out = 0.15 + 0.85 * out
    return out


def fabric():
    """Upholstery: a fine weave over a soft mottle."""
    yy, xx = np.mgrid[:N, :N]
    weave = 0.5 + 0.25 * np.sin(2 * np.pi * xx / 4) * np.sin(2 * np.pi * yy / 4)
    mottle = periodic_noise(2.4, seed=21)
    return 0.78 + 0.1 * weave + 0.12 * mottle


def velvet():
    """Curtain velvet: deep vertical folds (a few across the tile) catching the light, and a nap."""
    x = np.arange(N)[None, :] / N
    folds = 0.5 + 0.5 * np.cos(2 * np.pi * x * 3 + 0.4 * np.sin(2 * np.pi * x * 2))
    nap = periodic_noise(1.4, 1.0, 12, 31)
    return np.broadcast_to(0.42 + 0.48 * folds ** 1.5, (N, N)) + 0.1 * nap


def carpet():
    """A cinema's carpet: a repeating motif of rings and diamonds, two tones, a wool fuzz over it."""
    yy, xx = np.mgrid[:N, :N] / N
    cells = 4
    u = (xx * cells) % 1 - 0.5
    v = (yy * cells) % 1 - 0.5
    ring = np.abs(np.sqrt(u * u + v * v) - 0.3) < 0.04
    diamond = (np.abs(u) + np.abs(v)) < 0.12
    offset_u = ((xx * cells + 0.5) % 1) - 0.5
    offset_v = ((yy * cells + 0.5) % 1) - 0.5
    star = (np.abs(offset_u) < 0.02) | (np.abs(offset_v) < 0.02)
    star &= (np.abs(offset_u) + np.abs(offset_v)) < 0.16
    motif = np.where(ring | diamond | star, 1.0, 0.0)
    fuzz = periodic_noise(0.8, seed=41)
    return 0.6 + 0.3 * motif + 0.1 * fuzz


def rug():
    """A wool rug, laid once across its whole size: a border of bands, a medallion, the wool's fuzz."""
    yy, xx = np.mgrid[:N, :N] / N
    edge = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy))
    border = ((edge > 0.04) & (edge < 0.07)) | ((edge > 0.10) & (edge < 0.115))
    cx, cy = xx - 0.5, yy - 0.5
    medallion = (np.abs(cx) / 0.28 + np.abs(cy) / 0.2) < 1
    inner = (np.abs(cx) / 0.2 + np.abs(cy) / 0.13) < 1
    tone = np.where(border, 0.62, np.where(medallion & ~inner, 0.7, np.where(inner, 0.9, 0.82)))
    tone = np.where(edge < 0.02, 0.7, tone)
    return tone + 0.12 * periodic_noise(0.6, seed=51) - 0.06


def stone():
    """Stacked stone: courses of irregular blocks, each its own shade and texture, in dark mortar."""
    out = np.zeros((N, N))
    rough = periodic_noise(1.8, seed=61)
    y = 0
    courses = [36, 44, 30, 52, 40, 38, 48, 34, 46, 40, 54, 30]
    while y < N:
        h = courses[(y // 7) % len(courses)]
        h = min(h, N - y)
        x = rng.integers(0, 60)
        while x < N + 60:
            w = int(rng.integers(50, 130))
            shade = rng.uniform(0.62, 1.0)
            x0, x1 = x % N, (x + w) % N
            cols = np.arange(x, x + w) % N
            out[y:y + h, cols] = shade
            out[y:y + h, x0:x0 + 3] = 0.25 if x0 + 3 <= N else out[y:y + h, x0:x0 + 3]
            x += w
        out[y:y + 3] = 0.25
        y += h
    return out * (0.8 + 0.2 * rough)


def books():
    """A shelf's row of spines, in colour: cloth and leather, a few gold bands, the shelf's shadow above."""
    out = np.zeros((N, N, 3))
    palette = np.array([
        (0.42, 0.10, 0.09), (0.12, 0.16, 0.30), (0.16, 0.26, 0.18), (0.78, 0.72, 0.60), (0.08, 0.08, 0.09),
        (0.55, 0.38, 0.18), (0.30, 0.12, 0.20), (0.62, 0.55, 0.42), (0.20, 0.30, 0.34), (0.70, 0.30, 0.12),
    ])
    out[:] = (0.05, 0.04, 0.035)
    x = 0
    while x < N:
        w = int(rng.integers(12, 34))
        top = int(N * rng.uniform(0.0, 0.3))
        colour = palette[rng.integers(0, len(palette))] * rng.uniform(0.8, 1.1)
        x1 = min(N, x + w)
        out[top:, x:x1] = colour
        shade = 0.85 + 0.15 * np.sin(np.linspace(0, np.pi, x1 - x))   # a round spine
        out[top:, x:x1] *= shade[None, :, None]
        for band in rng.choice([0.2, 0.35, 0.75, 0.85], size=rng.integers(0, 3), replace=False):
            yb = int(top + (N - top) * band)
            out[yb:yb + 4, x + 2:x1 - 2] = (0.75, 0.6, 0.3)
        out[top:, x:x + 1] *= 0.5                                       # the gap between books
        if rng.random() < 0.08:                                         # now and then a gap
            x1 = min(N, x1 + int(rng.integers(10, 30)))
        x = x1
    out *= 0.85 + 0.15 * periodic_noise(1.0, seed=71)[:, :, None]
    return out


def seats(back=False):
    """A cinema bench as seats: one cushion a tile, its armrest a dark band at the tile's edge."""
    x = np.arange(N)[None, :] / N
    y = np.arange(N)[:, None] / N
    cushion = 0.86 + 0.14 * np.sin(np.pi * x) ** 0.6
    arm = np.where((x < 0.05) | (x > 0.95), 0.35, 1.0)
    if back:
        channels = 0.92 + 0.08 * np.cos(2 * np.pi * x * 5) ** 2
        top = np.where(y < 0.08, 0.8, 1.0)
        base = cushion * arm * channels * top
    else:
        base = cushion * arm * np.where(y < 0.1, 0.85, 1.0)
    return np.broadcast_to(base, (N, N)) * (0.9 + 0.1 * fabric())


def panel():
    """An acoustic wall panel: cloth over vertical channels."""
    x = np.arange(N)[None, :] / N
    channels = 0.85 + 0.15 * (np.abs(np.sin(np.pi * x * 8)) ** 0.3)
    return np.broadcast_to(channels, (N, N)) * fabric()


def art_abstract():
    """A mid-century print: warm discs and bars on cream."""
    yy, xx = np.mgrid[:N, :N] / N
    out = np.ones((N, N, 3)) * (0.86, 0.81, 0.70)
    shapes = [((0.34, 0.40), 0.22, (0.78, 0.36, 0.16)), ((0.62, 0.58), 0.16, (0.15, 0.28, 0.33)),
              ((0.48, 0.30), 0.09, (0.86, 0.62, 0.22))]
    for (cx, cy), r, c in shapes:
        disc = (xx - cx) ** 2 + (yy - cy) ** 2 < r * r
        out[disc] = c
    out[(yy > 0.74) & (yy < 0.78) & (xx > 0.18) & (xx < 0.82)] = (0.12, 0.10, 0.09)
    out[(xx > 0.70) & (xx < 0.73) & (yy > 0.20) & (yy < 0.74)] = (0.55, 0.20, 0.12)
    paper = 0.94 + 0.06 * periodic_noise(0.8, seed=81)
    return out * paper[:, :, None]


def art_landscape():
    """A misty mountain painting, in the lake's colours: layered ridges fading into a pale sky."""
    yy, xx = np.mgrid[:N, :N] / N
    sky = np.stack([0.80 - 0.25 * yy, 0.76 - 0.2 * yy, 0.78 - 0.1 * yy], axis=2)
    out = sky.copy()
    layers = [(0.42, (0.55, 0.58, 0.66)), (0.55, (0.38, 0.42, 0.52)), (0.68, (0.22, 0.26, 0.34)), (0.80, (0.10, 0.13, 0.17))]
    for i, (base, colour) in enumerate(layers):
        ridge = periodic_noise(3.0, 1.0, 1.0, 90 + i)[N // 2]
        height = base - 0.12 * (ridge - 0.5) * (1.4 - i * 0.2)
        mask = yy > height[None, :]
        out[mask] = np.array(colour)[None, :] * np.ones_like(out)[mask]
    brush = 0.92 + 0.08 * periodic_noise(1.2, 3.0, 1.0, 99)
    return out * brush[:, :, None]


def hull():
    """A spacecraft's inside: white panels in a grid, their seams, rows of rivets, a faint wear."""
    yy, xx = np.mgrid[:N, :N]
    out = np.ones((N, N)) * 0.92
    cell = N // 2
    seam = (xx % cell < 3) | (yy % cell < 3)
    out[seam] = 0.55
    rivets = ((xx % cell - 12) % (cell // 4) < 4) & (((yy % cell) - 12) % (cell - 24) < 4)
    out[rivets] = 0.7
    inner = ((xx % cell) > 40) & ((xx % cell) < cell - 40) & ((yy % cell) > 40) & ((yy % cell) < cell - 40)
    out = np.where(inner & ((xx % cell == 41) | (yy % cell == 41)), 0.8, out)
    return out * (0.94 + 0.06 * periodic_noise(1.4, seed=111))


def grating():
    """A metal deck's tread plate: raised diamonds in a herringbone, scuffed."""
    yy, xx = np.mgrid[:N, :N] / N
    cells = 16
    u = (xx * cells) % 1 - 0.5
    v = (yy * cells) % 1 - 0.5
    flip = ((np.floor(xx * cells) + np.floor(yy * cells)) % 2) * 2 - 1
    a = (u + flip * v) / 1.414
    b = (u - flip * v) / 1.414
    diamond = (np.abs(a) < 0.32) & (np.abs(b) < 0.07)
    out = np.where(diamond, 0.95, 0.72)
    scuff = periodic_noise(1.6, seed=121)
    return out * (0.85 + 0.15 * scuff)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("wood", wood())
    save("planks", planks())
    save("weathered", planks(boards=1, worn=True))
    save("fabric", fabric())
    save("velvet", velvet())
    save("carpet", carpet())
    save("rug", rug())
    save("stone", stone())
    save("books", books(), colour=True)
    save("seats", seats())
    save("seatback", seats(back=True))
    save("panel", panel())
    save("art_abstract", art_abstract(), colour=True)
    save("art_landscape", art_landscape(), colour=True)
    save("hull", hull())
    save("grating", grating())
