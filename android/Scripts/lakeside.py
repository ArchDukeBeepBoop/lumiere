"""Lumiere's Lakeside: a mountain lake at dusk, 4096 x 2048 equirect, for a skybox on a Quest.

You float over still water at blue hour. The sun set a few minutes ago behind a
low pass 70 degrees round from the picture's centre (longitude 110), so the sky
there holds a peach and rose afterglow that fades round the horizon into slate
blue, with the faint pink Belt of Venus over the Earth's shadow opposite.
Overhead it deepens to indigo and the first few stars show. Thin streaks of
high cloud catch the afterglow from below near the pass and stay cool elsewhere.

Ranges of mountains ring the lake, each the skyline of ridged fractal noise at
its own distance, so the far ones are hazier, bluer (warmer toward the glow) and
smaller, with mist lying at their feet. Dark spruce stand on the near shore.
The water mirrors all of it: each pixel of lake is a ray from your eyes (1.7 m
up) to a rippled surface, reflected and looked up in the sky above, so ripples
grow as they come toward you, the afterglow breaks into a glitter path under
the pass, and Fresnel keeps the far water bright and the water at your feet
dark. Ripples finer than a pixel are filtered out and become a soft vertical
blur instead, as a camera sees them.

The picture's centre (longitude 180) is the calmest stretch of horizon, low
far hills over open water, where the film's screen floats; the glow sits beyond
the screen's edge at every size, so the film stays the brightest thing in view.
To move it, turn the skybox entity about its vertical axis.

Every feature is made in 3D direction space (sky, clouds, stars, water) or from
longitude-periodic functions (ridges, trees), so the wrap at longitude 0/360 is
seamless and nothing pinches at the zenith or nadir. Linear light throughout,
encoded to sRGB at the end with a little grain so the dark gradients don't band.
Deterministic (seeded), so a rebuild is the same lake.

    python3 lakeside.py [OUT.jpg] [--preview DIR]

writes OUT (by default the Quest's res/drawable-nodpi/lumiere_lakeside.jpg);
--preview also writes a small panorama and 90 degree views to DIR.
"""
import argparse
import os
import numpy as np
from PIL import Image

W, H = 4096, 2048
HALF = H // 2                      # the horizon lies between rows HALF-1 and HALF
PX = 180.0 / H                     # degrees per pixel, down and across
PXR = np.pi / H                    # the same in radians
GLOW_LON = 110.0                   # where the sun went down
SUN_EL = -5.0                      # and how far below the horizon it is now
SCREEN_LON = 180.0                 # where the film's screen floats
EYE_M = 1.7                        # your eyes above the water
SEED = 2207
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../quest/src/main/res/drawable-nodpi/lumiere_lakeside.jpg")

LON = (np.arange(W) + 0.5) * PX                                     # column centres, degrees
LAT_UP = 90 - (np.arange(HALF) + 0.5) * PX                          # the sky's rows, degrees
SS = 4                                                              # skylines are drawn 4x across
LON_SS = (np.arange(W * SS) + 0.5) * PX / SS


def rng(k):
    """A generator per feature, so tuning one doesn't reshuffle the rest."""
    return np.random.default_rng([SEED, k])


def lin(c):
    c = np.asarray(c, np.float32) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def wrap(d):
    """Signed difference in longitude, -180..180."""
    return (d + 180) % 360 - 180


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def bump(lon, centre, width):
    return np.exp(-(wrap(lon - centre) / width) ** 2)


def summit(lon, centre, width):
    """A massif's rise: steep near its summit, with long tails, so its crests stand at different heights."""
    return 1 / (1 + (wrap(lon - centre) / width) ** 2)


def ramp(el, stops):
    """Colour stops by elevation, eased: interpolated in sqrt(elevation) and smoothed, so no kinks."""
    u = np.linspace(0, 1, 2048)
    deg = 90 * u * u
    cols = lin([s[1] for s in stops])
    table = np.stack([np.interp(deg, [s[0] for s in stops], cols[:, c]) for c in range(3)], -1)
    k = np.exp(-0.5 * (np.arange(-60, 61) / 24.0) ** 2)
    k /= k.sum()
    padded = np.concatenate([np.repeat(table[:1], 60, 0), table, np.repeat(table[-1:], 60, 0)])
    table = np.stack([np.convolve(padded[:, c], k, "valid") for c in range(3)], -1)
    ui = np.sqrt(np.clip(el, 0, 90) / 90)
    return np.stack([np.interp(ui, u, table[:, c]) for c in range(3)], -1).astype(np.float32)


def fractal(g, kmin, kmax, beta, n=W):
    """Periodic 1D noise round the horizon: a power-law spectrum with random phases, unit spread."""
    spec = np.zeros(n // 2 + 1, np.complex128)
    k = np.arange(kmin, min(kmax, n // 2) + 1)
    spec[k] = k ** (-beta / 2) * np.exp(1j * g.uniform(0, 2 * np.pi, k.size))
    s = np.fft.irfft(spec, n)
    return (s / s.std()).astype(np.float32)


class Perlin:
    """2D gradient noise on a plane (the cloud deck, the lake), roughly -1..1, with its gradient."""

    def __init__(self, g):
        p = g.permutation(256)
        self.perm = np.concatenate([p, p])
        a = g.uniform(0, 2 * np.pi, 256)
        self.gx, self.gy = np.cos(a).astype(np.float32), np.sin(a).astype(np.float32)

    def grad(self, x, y):
        xf, yf = np.floor(x), np.floor(y)
        fx, fy = (x - xf).astype(np.float32), (y - yf).astype(np.float32)
        xi, yi = xf.astype(np.int64) & 255, yf.astype(np.int64) & 255
        p, gx, gy = self.perm, self.gx, self.gy
        h00, h10 = p[p[xi] + yi], p[p[xi + 1] + yi]
        h01, h11 = p[p[xi] + yi + 1], p[p[xi + 1] + yi + 1]
        n00, n10 = gx[h00] * fx + gy[h00] * fy, gx[h10] * (fx - 1) + gy[h10] * fy
        n01, n11 = gx[h01] * fx + gy[h01] * (fy - 1), gx[h11] * (fx - 1) + gy[h11] * (fy - 1)
        u, v = fx * fx * fx * (fx * (fx * 6 - 15) + 10), fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        du, dv = 30 * fx * fx * (fx - 1) ** 2, 30 * fy * fy * (fy - 1) ** 2
        a, b = n00 + u * (n10 - n00), n01 + u * (n11 - n01)
        ax = gx[h00] + u * (gx[h10] - gx[h00]) + du * (n10 - n00)
        bx = gx[h01] + u * (gx[h11] - gx[h01]) + du * (n11 - n01)
        ay, by = gy[h00] + u * (gy[h10] - gy[h00]), gy[h01] + u * (gy[h11] - gy[h01])
        return 1.41 * (a + v * (b - a)), 1.41 * (ax + v * (bx - ax)), 1.41 * (ay + v * (by - ay) + dv * (b - a))

    def __call__(self, x, y):
        return self.grad(x, y)[0]


def fbm(noises, x, y, footprint, octaves, gain=0.5):
    """Fractal noise whose octaves fade as they shrink below a pixel's footprint (no aliasing at the horizon)."""
    total = np.zeros(np.shape(x), np.float32)
    f, a, norm = 1.0, 1.0, 0.0
    for o in range(octaves):
        att = np.clip(1.6 - 2.4 * f * footprint, 0, 1)
        c, s = np.cos(0.7 * o), np.sin(0.7 * o)               # each octave turned, so the lattice never shows
        total += a * att * noises[o % len(noises)](f * (c * x - s * y) + 17.3 * o, f * (s * x + c * y) - 9.1 * o)
        norm += a
        f, a = f * 2.03, a * gain
    return total / norm


def blur(img, sx, sy):
    """Gaussian blur: round the horizon it wraps, up and down it mirrors."""
    out = np.empty_like(img)
    kx = np.exp(-2 * (np.pi * np.arange(img.shape[1] // 2 + 1) * sx / img.shape[1]) ** 2)
    pad = int(4 * sy) + 2
    rows = img.shape[0] + 2 * pad
    ky = np.exp(-2 * (np.pi * np.fft.rfftfreq(rows) * sy) ** 2)[:, None]
    for c in range(img.shape[2]):
        ch = np.fft.irfft(np.fft.rfft(img[..., c], axis=1) * kx, img.shape[1], axis=1)
        ch = np.concatenate([ch[pad:0:-1], ch, ch[-2:-pad - 2:-1]])
        ch = np.fft.irfft(np.fft.rfft(ch, axis=0) * ky, rows, axis=0)
        out[..., c] = ch[pad:pad + img.shape[0]]
    return out


def bilinear(img, r, c):
    """Samples img at fractional (row, column), wrapping columns, clamping rows."""
    r = np.clip(r, 0, img.shape[0] - 1.001)
    r0, c0 = np.floor(r).astype(np.int64), np.floor(c).astype(np.int64)
    fr, fc = (r - r0)[..., None].astype(np.float32), (c - c0)[..., None].astype(np.float32)
    c0 %= img.shape[1]
    c1 = (c0 + 1) % img.shape[1]
    top = img[r0, c0] * (1 - fc) + img[r0, c1] * fc
    bot = img[r0 + 1, c0] * (1 - fc) + img[r0 + 1, c1] * fc
    return top * (1 - fr) + bot * fr


# --- The sky -------------------------------------------------------------------------------

def sky():
    lat, lon = np.radians(LAT_UP)[:, None], np.radians(LON)[None, :]
    x, y, z = np.cos(lat) * np.cos(lon), np.sin(lat) * np.ones_like(lon), np.cos(lat) * np.sin(lon)
    el = np.broadcast_to(LAT_UP[:, None], (HALF, W))
    dl = wrap(LON[None, :] - GLOW_LON)

    # Away from the glow: the Earth's shadow, slate blue on the horizon, the Belt of Venus over it.
    away = ramp(el, [(0, (50, 56, 86)), (3, (54, 58, 90)), (9, (78, 72, 106)), (16, (72, 72, 110)),
                     (30, (50, 60, 104)), (50, (32, 42, 86)), (70, (22, 29, 68)), (90, (16, 21, 56))])
    # Toward it: apricot on the horizon, then peach, rose, lilac, into the blue hour's blue.
    toward = ramp(el, [(0, (236, 152, 100)), (2, (230, 152, 110)), (5, (214, 144, 124)), (9, (184, 126, 136)),
                       (14, (146, 110, 144)), (20, (106, 98, 146)), (28, (76, 84, 134)), (40, (52, 64, 112)),
                       (55, (34, 44, 90)), (70, (22, 29, 68)), (90, (16, 21, 56))])
    # The afterglow's arch: wide at its foot, flattening as it rises.
    width = 66 - 12 * smoothstep(0, 30, el)
    w = np.exp(-np.abs(dl / width) ** 1.7) * 0.9 + 0.1 * np.exp(-(dl / 140) ** 2)
    out = away + w[..., None] * (toward - away)
    # A warmer heart just above where the sun went down.
    heart = np.exp(-(dl / 22) ** 2 - ((el - SUN_EL) / 7.5) ** 2)
    out += heart[..., None] * lin((150, 92, 40)) * 0.9

    sun = np.array([np.cos(np.radians(SUN_EL)) * np.cos(np.radians(GLOW_LON)), np.sin(np.radians(SUN_EL)),
                    np.cos(np.radians(SUN_EL)) * np.sin(np.radians(GLOW_LON))])
    gamma = np.degrees(np.arccos(np.clip(x * sun[0] + y * sun[1] + z * sun[2], -1, 1)))
    out = clouds(out, x, y, z, el, gamma)
    return stars(out)


def clouds(out, x, y, z, el, gamma):
    """Thin high streaks on a deck above you: perspective crowds them toward the horizon, where they thin out."""
    g = rng(3)
    noises = [Perlin(g) for _ in range(4)]
    yy = np.maximum(y, 0.03)
    px, pz = x / yy, z / yy                                  # where your gaze meets the deck, in deck heights
    foot = PXR / (yy * yy)                                   # a pixel's footprint there
    wind = np.radians(GLOW_LON + 58)
    along, across = px * np.cos(wind) + pz * np.sin(wind), -px * np.sin(wind) + pz * np.cos(wind)
    bend = fbm(noises, along * 0.18 + 3.1, across * 0.3 - 1.7, foot * 0.3, 3)
    streak = fbm(noises, along * 0.32 + 5.3, (across + 0.9 * bend) * 2.4, foot * 2.4, 7, 0.58)
    where = fbm(noises, px * 0.28 + 4.2, pz * 0.28 - 2.6, foot * 0.28, 3)
    cover = smoothstep(-0.08, 0.42, streak * 0.85 + where * 0.75 - 0.05)
    cover *= smoothstep(3, 14, el) * (1 - 0.65 * smoothstep(40, 80, el))
    density = (cover ** 1.6 * 0.6)[..., None]
    # Lit from below by the afterglow near it; overhead and opposite they're already in the Earth's
    # shadow, so a cool grey-blue barely apart from the sky.
    lit = np.clip(np.exp(-(gamma / 48) ** 2) * 1.1 + 0.04 * np.exp(-(gamma / 100) ** 2), 0, 1)[..., None]
    warm = lin((222, 140, 126)) * (0.5 + 0.5 * smoothstep(45, 8, el))[..., None]
    cool = out * 0.86 + lin((12, 14, 26))
    tint = cool + lit * (warm - cool)
    return out * (1 - density) + tint * density


def stars(out):
    """A few faint stars, round on the sphere (so wider in pixels toward the zenith), gone by the horizon."""
    g = rng(4)
    count = 700
    lat = np.degrees(np.arcsin(g.uniform(np.sin(np.radians(15)), 1, count)))      # even over the cap
    lon = g.uniform(0, 360, count)
    mag = g.pareto(2.4, count) + 1
    hot = g.random(count)
    for la, lo, m, t in zip(lat, lon, mag, hot):
        fade = smoothstep(18, 72, la) * (1 - 0.85 * bump(lo, GLOW_LON, 60) * smoothstep(60, 20, la))
        b = min(0.045 * m, 0.24) * fade
        if b < 0.004:
            continue
        row, col = (90 - la) / PX - 0.5, lo / PX - 0.5
        cosl = max(np.cos(np.radians(la)), 0.03)
        r0, r1 = max(int(row) - 3, 0), min(int(row) + 5, HALF)
        span = min(int(3 / cosl) + 2, W // 2)
        cols = np.arange(int(col) - span, int(col) + span + 1)
        dy = (np.arange(r0, r1)[:, None] - row) * PX
        dx = wrap((cols[None, :] - col) * PX) * cosl
        spot = b * np.exp(-(dy * dy + dx * dx) / (2 * 0.045 ** 2))
        tint = lin((214, 224, 255)) if t < 0.7 else lin((255, 234, 206))
        out[r0:r1, cols % W] += spot[..., None] * tint
    return out


# --- The land ------------------------------------------------------------------------------

def octave(g, k):
    """One octave of periodic noise, cycles k to 2k round the horizon, sampled 4x across."""
    return fractal(g, int(k), int(2 * k) - 1, 0.0, W * SS)


def skyline(g, dist_km, relief_m, k0, env, sharp=1.35, warp=3.0):
    """A range's skyline in degrees: ridged multifractal noise (sharp crests, soft valleys), scaled by env, at a distance."""
    x = (LON_SS + warp * fractal(g, 2, 12, 2.5, W * SS)) % 360
    total, weight, norm = np.zeros(W * SS, np.float32), np.ones(W * SS, np.float32), 0.0
    for o in range(7):
        n = np.interp(x, LON_SS, octave(g, k0 * 2 ** o), period=360)
        s = np.clip(1 - np.abs(n) / 2.4, 0, 1) ** sharp * weight
        weight = np.clip(s * 1.8, 0.4, 1)                     # crests get the most detail, valleys some
        total += s * 0.5 ** o
        norm += 0.5 ** o
    # Broad shoulders under the crests, so summits stand at different heights.
    smooth = 0.5 + 0.2 * fractal(g, max(k0 // 2, 1), 40 * k0, 2.3, W * SS)
    h = relief_m * env * (0.64 * total / norm + 0.36 * smooth) ** 1.3
    drop = (dist_km * 1000) ** 2 / (2 * 6.371e6)                          # the Earth curves away
    return np.degrees(np.arctan2(h - drop, dist_km * 1000))


def ranges():
    """The skylines, far to near, each with its distance (km) for the haze."""
    g = rng(1)
    lon = LON_SS
    notch = 1 - 0.85 * bump(lon, GLOW_LON, 8) - 0.1 * bump(lon, GLOW_LON, 20)
    calm = 1 - 0.55 * bump(lon, SCREEN_LON, 26)
    far_env = (0.28 + 1.1 * summit(lon, GLOW_LON - 33, 6) + 0.5 * summit(lon, GLOW_LON + 30, 5)
               + 0.85 * summit(lon, 328, 7) + 0.3 * bump(lon, 262, 24) + 0.3 * summit(lon, 22, 6)
               + 0.08 * fractal(g, 1, 6, 1.0, W * SS)) * notch * calm
    far2_env = (0.34 + 0.30 * bump(lon, GLOW_LON + 52, 16) + 0.30 * bump(lon, 236, 22) + 0.28 * bump(lon, 300, 16)
                + 0.24 * bump(lon, 40, 22) + 0.1 * fractal(g, 1, 6, 1.0, W * SS)) * notch * calm
    mid_env = np.clip(0.2 + 0.75 * bump(lon, 214, 26) + 0.7 * bump(lon, 288, 20) + 0.6 * bump(lon, 52, 22)
                      + 0.45 * bump(lon, GLOW_LON - 52, 12) + 0.25 * fractal(g, 1, 5, 1.0, W * SS), 0, None) \
        * (1 - 0.9 * bump(lon, GLOW_LON, 18)) * (1 - 0.6 * bump(lon, SCREEN_LON, 18))
    return [(skyline(g, 24, 4200, 9, far_env), 24), (skyline(g, 15, 1500, 12, far2_env), 15),
            (skyline(g, 6.5, 420, 12, mid_env, 1.4), 6.5)]


def shore_trees():
    """Spruce along the near shore, about 700 m off: tiered cones, 0.5-2 degrees, in groves over a mass
    of lower crowns. Coverage at 4x across and down, averaged to pixels; rows just above the horizon."""
    g = rng(2)
    rows = int(2.6 / PX) * SS
    band = np.zeros((rows, W * SS), np.float32)
    sx, sy = PX / SS, PX / SS
    yy = (rows - 1 - np.arange(rows) + 0.5) * sy                       # degrees up, per supersampled row
    shore = 0.07
    grove = np.clip(0.5 + 0.38 * fractal(g, 18, 90, 1.5, W * SS), 0, 1)  # taller stands and thinner gaps
    crowns = fractal(g, 300, 1600, 1.2, W * SS)
    for a, b in [(GLOW_LON + 30, GLOW_LON + 62), (200, 250), (276, 336), (16, 56)]:
        span = (b - a) % 360
        cols = np.arange(int(a / sx), int((a + span) / sx))
        ends = smoothstep(0, 0.12, (cols * sx - a) / span) * smoothstep(1, 0.88, (cols * sx - a) / span)
        # The mass of lower crowns the tallest rise from: a ragged band about half their height.
        mass = shore + ends * (0.22 + 0.5 * grove[cols % (W * SS)]) * (0.9 + 0.1 * crowns[cols % (W * SS)])
        band[:, cols % (W * SS)] = np.maximum(band[:, cols % (W * SS)], yy[:, None] <= mass[None, :])
        c = a + g.uniform(0, 0.2)
        while c < a + span:
            t = (c - a) / span
            edge = smoothstep(0, 0.12, t) * smoothstep(1, 0.88, t)
            stand = grove[int(c % 360 / sx)]
            tall = float(np.clip((0.5 + 0.9 * stand) * (0.7 + 0.55 * g.random() ** 1.5) * (0.5 + 0.5 * edge), 0.45, 2.0))
            halfw = tall * g.uniform(0.2, 0.27)
            if g.random() < 0.25 + 0.75 * edge * smoothstep(0.08, 0.3, stand):
                tiers, phase = g.integers(6, 10), g.random()
                jl, jr = g.uniform(0.7, 1.2, 16), g.uniform(0.7, 1.2, 16)
                top = shore + tall
                r0 = max(rows - 1 - int(top / sy) - 2, 0)
                ys = yy[r0:]
                tt = np.clip((ys - shore) / tall, 0, 1)
                s = (tt * tiers + phase) % 1
                tier = np.floor(tt * tiers + phase).astype(int) % 16
                shape = halfw * (1 - tt) ** 0.85 * (0.55 + 0.45 * (1 - s) ** 1.3)
                shape = np.where(tt > 0.9, np.minimum(shape, halfw * 0.08 * (1 - tt) / 0.1 + 0.004), shape)  # the leader
                cc = np.arange(int((c - halfw * 1.3) / sx), int((c + halfw * 1.3) / sx) + 2)
                dx = (cc + 0.5) * sx - c
                wide = np.where(dx[None, :] < 0, jl[tier][:, None], jr[tier][:, None]) * shape[:, None]
                inside = (np.abs(dx)[None, :] <= wide) & (ys[:, None] <= top)
                band[r0:, cc % (W * SS)] = np.maximum(band[r0:, cc % (W * SS)], inside)
            c += halfw * 2 * g.uniform(0.35, 0.7)
    return band.reshape(rows // SS, SS, W, SS).mean((1, 3))


def landscape(upper):
    """The ranges, the treeline and the mist over the water at their feet, laid over the sky."""
    out = upper.copy()
    horizon = upper[HALF - 6:HALF - 2].mean(0)                # the sky just above the horizon, per column
    blue = lin((58, 68, 108))
    toward = bump(LON, GLOW_LON, 70)[:, None]
    dark = lin((12, 14, 23)) * toward + lin((20, 20, 33)) * (1 - toward)  # faces lit a little by the glow opposite
    band = int(12 / PX)
    el = (HALF - np.arange(HALF - band, HALF) - 0.5)[:, None] * PX
    region = out[HALF - band:]
    for sky_line, km in ranges():
        cov = np.clip((sky_line.reshape(W, SS)[None] - el[..., None]) / PX + 0.5, 0, 1).mean(-1)
        haze = 1 - np.exp(-km / 24.0)
        # The air between you and them lies in the Earth's shadow now: lit by the sky, so bluer and
        # dimmer than the glow above, warming only a little toward it.
        air = blue * (0.55 + 0.1 * haze) + horizon * (0.36 - 0.1 * haze)
        mist = 0.55 * np.exp(-el / np.degrees(np.arctan(0.14 / km)))  # a 140 m mist on the water
        fog = haze + (1 - haze) * mist
        colour = dark[None] + fog[..., None] * (air[None] - dark[None])
        region = region * (1 - cov[..., None]) + colour * cov[..., None]
    trees = shore_trees()
    tb = trees.shape[0]
    green = lin((7, 9, 14)) + 0.05 * (horizon - lin((7, 9, 14)))
    region[-tb:] = region[-tb:] * (1 - trees[..., None]) + green[None] * trees[..., None]
    # A low breath of mist over the whole shore line, thicker in places.
    veil = 0.22 * np.exp(-el / 0.35) * (0.6 + 0.4 * np.clip(fractal(rng(5), 3, 60, 1.8), -1, 1))[None, :]
    region = region + veil[..., None] * (horizon[None] - region)
    out[HALF - band:] = region
    return out


# --- The water -----------------------------------------------------------------------------

def water(upper):
    """Each row below the horizon: a ray to the rippled lake, reflected into the sky above."""
    g = rng(6)
    wind = np.radians(GLOW_LON + 58)
    octaves = []
    for o in range(7):
        lam = 3.2 / 2.03 ** o                                 # metres, 3.2 m down to 5 cm
        th = wind + g.normal(0, 0.35)
        slope = 0.024 * min(1.0, (0.8 / lam) ** 0.5)          # how much each adds: short ripples are steepest
        octaves.append((1 / lam, th, slope, Perlin(g), g.uniform(0, 256, 2)))
    patches = [Perlin(g) for _ in range(3)]
    stretch = 0.32                                            # crests run long across the wind

    sig_v = np.array([2.0, 5, 11, 24, 52])
    sig_h = np.array([1.2, 1.5, 2.0, 2.6, 3.2])
    levels = [blur(upper, a, b) for a, b in zip(sig_h, sig_v)]
    body = lin((8, 12, 19))
    out = np.empty((HALF, W, 3), np.float32)
    lon = np.radians(LON)[None, :]
    cl, sl = np.cos(lon), np.sin(lon)
    for r0 in range(0, HALF, 128):
        dep = np.radians((np.arange(r0, r0 + 128) + 0.5) * PX)[:, None]
        dist = EYE_M / np.tan(dep)
        px, pz = dist * cl, dist * sl
        fr, ft = EYE_M / np.sin(dep) ** 2 * PXR, dist * PXR   # a pixel's footprint, toward you and across
        calm = fbm(patches, px / 60 + 7.0, pz / 60 - 3.0, fr / 60, 3)
        breeze = 0.3 + 0.7 * smoothstep(-0.3, 0.3, calm)
        sx = np.zeros(px.shape, np.float32)
        sz = np.zeros(px.shape, np.float32)
        lost = np.zeros(px.shape, np.float32)
        for f, th, slope, noise, (ox, oz) in octaves:
            ct, st = np.cos(th), np.sin(th)
            # Noise coordinates: across the crests at full rate, along them stretched.
            qa, qb = f * (px * ct + pz * st), f * stretch * (-px * st + pz * ct)
            # How far a pixel steps in noise space, toward you and across: big steps are filtered out.
            step_r = f * fr * np.hypot(cl * ct + sl * st, stretch * (-cl * st + sl * ct))
            step_t = f * ft * np.hypot(-sl * ct + cl * st, stretch * (sl * st + cl * ct))
            att = np.exp(-(np.maximum(step_r, step_t) / 0.3) ** 2).astype(np.float32)
            _, ga, gb = noise.grad(qa + ox, qb + oz)
            amp = slope * att / 1.6
            sx += amp * (ga * ct - gb * stretch * st)
            sz += amp * (ga * st + gb * stretch * ct)
            lost += slope ** 2 * (1 - att * att)
        sx, sz, lost = sx * breeze, sz * breeze, lost * breeze ** 2
        nrm = 1 / np.sqrt(1 + sx * sx + sz * sz)
        nx, ny, nz = -sx * nrm, nrm, -sz * nrm
        vx, vy, vz = np.cos(dep) * cl, -np.sin(dep) * np.ones_like(cl), np.cos(dep) * sl
        d = vx * nx + vy * ny + vz * nz
        rx, ry, rz = vx - 2 * d * nx, vy - 2 * d * ny, vz - 2 * d * nz
        ry = np.maximum(ry, np.sin(np.radians(0.03)))
        rlat = np.degrees(np.arcsin(np.clip(ry / np.sqrt(rx * rx + ry * ry + rz * rz), -1, 1)))
        rlon = np.degrees(np.arctan2(rz, rx)) % 360
        row, col = (90 - rlat) / PX - 0.5, rlon / PX - 0.5
        fres = (0.02 + 0.98 * (1 - np.clip(-d, 0, 1)) ** 5)[..., None]
        spread = np.sqrt(sig_v[0] ** 2 + (0.6 * np.sqrt(lost / 2) / PXR) ** 2)
        pos = np.interp(spread, sig_v, np.arange(len(sig_v)))
        refl = np.zeros(px.shape + (3,), np.float32)
        for j, level in enumerate(levels):
            wgt = np.clip(1 - np.abs(pos - j), 0, 1)[..., None]
            if wgt.max() > 0:
                refl += wgt * bilinear(level, row, col)
        out[r0:r0 + 128] = fres * refl * 0.86 + (1 - fres) * body
    return out


# --- Output ----------------------------------------------------------------------------------

def encode(img):
    """sRGB with a fine grain that survives the JPEG, so the dusk gradients don't band."""
    g = rng(9)
    grain = g.normal(0, 1, (H, W, 1)).astype(np.float32)
    grain = blur(grain, 0.55, 0.55)[..., 0]
    grain *= 0.9 / grain.std()
    s = srgb(img) * 255 + grain[..., None]
    return np.clip(np.round(s), 0, 255).astype(np.uint8)


def perspective(img, yaw, pitch, fov=90, w=1280, h=720):
    """A 90 degree view from inside the sphere, as you'd see it in the headset."""
    f = (w / 2) / np.tan(np.radians(fov) / 2)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    x, y = xs + 0.5 - w / 2, h / 2 - (ys + 0.5)
    a, p = np.radians(yaw), np.radians(pitch)
    fwd = np.array([np.cos(p) * np.cos(a), np.sin(p), np.cos(p) * np.sin(a)])
    right = np.array([-np.sin(a), 0, np.cos(a)])
    up = np.array([-np.sin(p) * np.cos(a), np.cos(p), -np.sin(p) * np.sin(a)])
    d = fwd * f + right * x[..., None] + up * y[..., None]
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    lat = np.degrees(np.arcsin(d[..., 1]))
    lon = np.degrees(np.arctan2(d[..., 2], d[..., 0])) % 360
    return bilinear(img.astype(np.float32), (90 - lat) / PX - 0.5, lon / PX - 0.5)


def previews(path, folder):
    os.makedirs(folder, exist_ok=True)
    img = np.asarray(Image.open(path).convert("RGB"))
    Image.fromarray(img).resize((2048, 1024), Image.LANCZOS).save(os.path.join(folder, "panorama.png"))
    views = {"glow": (GLOW_LON, 0), "away": (GLOW_LON + 180, 0), "water": (GLOW_LON, -30),
             "up": (GLOW_LON, 90), "seam": (0, 0), "screen": (SCREEN_LON, 4), "down": (GLOW_LON, -90)}
    for name, (yaw, pitch) in views.items():
        view = perspective(img, yaw, pitch)
        Image.fromarray(np.clip(view + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(folder, name + ".png"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?", default=OUT)
    ap.add_argument("--preview", metavar="DIR", help="also write a panorama and 90 degree views here")
    args = ap.parse_args()
    upper = landscape(sky())
    pixels = encode(np.concatenate([upper, water(upper)]))
    Image.fromarray(pixels).save(args.out, quality=90, optimize=True)
    luma = (pixels.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255
    solid = np.cos(np.radians(90 - (np.arange(H) + 0.5) * PX))[:, None]
    print("lakeside %s: %d KB, mean luminance %.1f%% (%.1f%% by solid angle)" % (
        os.path.basename(args.out), os.path.getsize(args.out) // 1024, luma.mean() * 100,
        (luma * solid).sum() / (solid.sum() * W) * 100))
    if args.preview:
        previews(args.out, args.preview)


if __name__ == "__main__":
    main()
