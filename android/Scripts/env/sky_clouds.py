"""Lumiere's Above the Clouds: golden hour over a sea of cumulus, 4096 x 2048 equirect, for a skybox on a Quest.

You float 4.3 km over the tops of a cumulus deck that runs out to the curve of the horizon, the sun 5
degrees up and 50 to the right of the screen, gold on the lit faces of the heaps and lavender in their
shade, the haze warm toward the sun and cool away from it; a few wisps of cirrus overhead. The deck is a
height field of cauliflower lobes at six scales, each column's ray marched out over it front to back,
with shadows felt for toward the sun; finer lobes fade below each pixel's footprint so the horizon
doesn't shimmer.

    python3 clouds.py [OUT.jpg] [--preview DIR]
"""
import argparse
import os
import numpy as np
from PIL import Image

W, H = 4096, 2048
HALF = H // 2                      # the horizon lies between rows HALF-1 and HALF
PX = 180.0 / H                     # degrees per pixel, down and across
PXR = np.pi / H                    # the same in radians
SUN_LON = 230.0                    # the sun: 50 degrees right of the screen
SUN_EL = 5.0                       # and this high
SCREEN_LON = 180.0                 # where the film's screen hangs
EYE_M = 4300.0                     # your eyes above the cloud sea's mean tops
R_EFF = 6.371e6 * 7 / 6            # the Earth's radius as light bends over it (m)
SEED = 3313
SS = 2                             # the cloud sea is drawn 2x across and 2x down
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../quest/src/main/res/drawable-nodpi/lumiere_clouds.jpg")

LON = (np.arange(W) + 0.5) * PX                                     # column centres, degrees
LAT_UP = 90 - (np.arange(HALF) + 0.5) * PX                          # the sky's rows, degrees
LON_SS = (np.arange(W * SS) + 0.5) * PX / SS
F32 = np.float32


def direction(lat, lon):
    la, lo = np.radians(lat), np.radians(lon)
    return np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)


SUN = np.array(direction(SUN_EL, SUN_LON), np.float64)


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


class Perlin:
    """2D gradient noise on a plane, roughly -1..1, with its gradient."""

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

# Toward the sun: peach and apricot haze on the horizon, then pale gold, a clean pale blue, deep blue overhead.
TOWARD = [(0, (220, 156, 112)), (2, (214, 154, 116)), (5, (192, 144, 122)), (10, (150, 128, 134)),
          (17, (108, 114, 144)), (26, (76, 96, 146)), (40, (54, 80, 140)), (60, (38, 64, 130)), (90, (26, 52, 118))]
# Away from it: a cooler, paler blue on the horizon with the faintest pink, deepening the same way.
AWAY = [(0, (116, 122, 152)), (3, (106, 116, 154)), (8, (90, 104, 150)), (16, (72, 92, 148)),
        (28, (56, 80, 142)), (45, (42, 68, 134)), (65, (32, 58, 124)), (90, (26, 52, 118))]
GLOW = lin((255, 190, 120))
AUREOLE = lin((255, 222, 170))


def sun_angle(x, y, z):
    return np.degrees(np.arccos(np.clip(x * SUN[0] + y * SUN[1] + z * SUN[2], -1, 1)))


def sky_colour(x, y, z):
    """The clear sky in each direction, linear: below the eye line it stays the horizon's haze. No sun disc."""
    el = np.degrees(np.arcsin(np.clip(y, -1, 1)))
    lon = np.degrees(np.arctan2(z, x)) % 360
    dl = np.radians(wrap(lon - SUN_LON))
    e = np.maximum(el, 0)
    toward, away = ramp(e, TOWARD), ramp(e, AWAY)
    # The warm side's reach round the horizon, wide at the foot of the sky and narrowing as it rises.
    w = ((1 + np.cos(dl)) / 2) ** (2.2 + 1.4 * smoothstep(0, 30, e))
    out = away + w[..., None] * (toward - away)
    gamma = sun_angle(x, y, z)
    glow = 0.55 * np.exp(-gamma / 1.4) + 0.16 * np.exp(-gamma / 5.0) + 0.07 * np.exp(-(gamma / 20) ** 2)
    out = out + glow[..., None] * GLOW + (0.6 * np.exp(-gamma / 0.45))[..., None] * AUREOLE
    return out.astype(np.float32)


def sun_disc(gamma):
    """The sun itself: a soft disc a little larger than life, white gold."""
    return (smoothstep(0.42, 0.26, gamma) * 3.0)[..., None] * lin((255, 244, 222))


def cirrus(out, x, y, z, el, gamma):
    """A few high wisps of cirrus on a deck above you, golden toward the sun and pale rose elsewhere."""
    g = rng(3)
    noises = [Perlin(g) for _ in range(4)]
    yy = np.maximum(y, 0.03)
    px, pz = x / yy, z / yy
    foot = PXR / (yy * yy)
    wind = np.radians(SUN_LON - 35)
    along, across = px * np.cos(wind) + pz * np.sin(wind), -px * np.sin(wind) + pz * np.cos(wind)
    bend = fbm(noises, along * 0.16 + 3.1, across * 0.28 - 1.7, foot * 0.3, 3)
    streak = fbm(noises, along * 0.3 + 5.3, (across + 0.9 * bend) * 2.2, foot * 2.2, 7, 0.58)
    where = fbm(noises, px * 0.2 + 4.2, pz * 0.2 - 2.6, foot * 0.2, 3)
    fibre = fbm(noises, along * 0.9 - 2.2, (across + 0.9 * bend) * 11, foot * 11, 4, 0.6)
    cover = smoothstep(0.05, 0.5, streak * 0.8 + where * 0.9 - 0.18) * smoothstep(-0.45, 0.35, fibre)
    cover *= smoothstep(4, 16, el)
    density = (cover ** 1.5 * 0.42)[..., None]
    lit = np.exp(-(gamma / 40) ** 2)[..., None]
    warm = lin((255, 214, 170)) * 0.95
    rose = lin((232, 206, 210)) * 0.7
    tint = rose + lit * (warm - rose)
    return out * (1 - density) + tint * density


def sky():
    lat, lon = LAT_UP[:, None], LON[None, :]
    x, y, z = direction(lat, lon)
    out = sky_colour(x, y, z)
    gamma = sun_angle(x, y, z)
    out = cirrus(out, x, y, z, np.broadcast_to(lat, out.shape[:2]), gamma)
    return out + sun_disc(gamma)


# --- The cloud sea ---------------------------------------------------------------------------

class Bubbles:
    """Cauliflower lobes: a sphere cap round a jittered point in every cell, of random radius, joined to its
    neighbours by a smooth maximum so the creases between lobes are rounded; about 0..1 in cell units, with
    its gradient, and how deep in a crease between two lobes each point lies."""
    N = 4096
    K = 0.2                                     # how round the creases are (cell units)

    def __init__(self, g, heap=False):
        self.heap = heap                        # a broad soft mound (smooth foot) instead of a round lobe
        self.jx = g.random(self.N).astype(F32)
        self.jy = g.random(self.N).astype(F32)
        self.r = g.uniform(0.5, 1.0, self.N).astype(F32)
        self.k1, self.k2 = int(g.integers(1 << 20, 1 << 28)) | 1, int(g.integers(1 << 20, 1 << 28)) | 1
        u = g.uniform(0, 300, (2, 1 << 16))
        self.mean = float(self(u[0], u[1], grad=False)[0].mean())

    def __call__(self, u, v, grad=True):
        uf, vf = np.floor(u), np.floor(v)
        fu, fv = (u - uf).astype(F32), (v - vf).astype(F32)
        ui, vi = uf.astype(np.int64), vf.astype(np.int64)
        best = np.zeros(fu.shape, F32)
        crease = np.zeros(fu.shape, F32)
        if grad:
            gu, gv = np.zeros(fu.shape, F32), np.zeros(fu.shape, F32)
        for di in (-1, 0, 1):
            hi = (ui + di) * self.k1
            for dj in (-1, 0, 1):
                h = hi ^ ((vi + dj) * self.k2)
                h = (h ^ (h >> 13)) & (self.N - 1)
                r = self.r[h]
                dx = fu - (di + self.jx[h])
                dy = fv - (dj + self.jy[h])
                base = np.maximum(1 - (dx * dx + dy * dy) / (r * r), 0)
                if self.heap:
                    cap = r * base * base * (3 - 2 * base)
                else:
                    root = np.sqrt(base)
                    cap = r * root
                w = np.clip(0.5 + 0.5 * (cap - best) / self.K, 0, 1)
                both = w * (1 - w)
                best = best + w * (cap - best) + self.K * both
                crease = np.maximum(crease, 4 * both * (cap > 0.04))
                if grad:
                    inv = w * 12 * base * (1 - base) / r if self.heap else w / (r * np.maximum(root, 0.3))
                    gu = gu - inv * dx - w * gu
                    gv = gv - inv * dy - w * gv
        if not grad:
            return best, crease
        return best, crease, gu, gv


# Cumulus at six scales: each lobe's cell (m) and how high it heaps (m).
DOMES = [(1500, 430), (660, 190), (290, 84), (128, 37), (56, 16), (25, 7)]
SOFT = [1.0, 1.0, 0.85, 0.65, 0.5, 0.4]                   # how much each scale shapes the light
DEEP = [1.4, 1.2, 0.9, 0.45, 0.2, 0.1]                   # and how much its hollows shade
PROBES = [18, 45, 110, 260, 600, 1400, 3200]           # how far toward the sun shadows are looked for (m)


class Tops:
    """The cloud tops as a height field over the plane round you (m above their mean)."""

    def __init__(self):
        g = rng(1)
        self.bub = [Bubbles(g, k < 2) for k in range(len(DOMES))]
        self.turn = g.uniform(0, 2 * np.pi, len(DOMES))
        self.shift = g.uniform(0, 400, (len(DOMES), 2))
        self.macro = [Perlin(g) for _ in range(3)]
        self.rough = Perlin(rng(2))

    def heap(self, px, pz, fp):
        """How heaped the cumulus are, region by region (about 0.3..1.4), and the deck's slow swell (m)."""
        m = fbm(self.macro, px / 16000 + 2.3, pz / 16000 - 5.1, fp / 16000, 3)
        swell = 140 * self.macro[2](px / 45000 - 1.7, pz / 45000 + 3.3)
        return np.clip(0.8 + 1.1 * m, 0.3, 1.45).astype(F32), swell.astype(F32)

    def __call__(self, px, pz, fp, which=None, grad=True):
        """Height (and gradient, and crease shading) at (px, pz), octaves finer than the footprint fp faded
        to their mean. which limits the octaves (the rest count at their mean), for the shadow probes."""
        heap, h = self.heap(px, pz, fp)
        knobs = np.clip(0.55 + 0.8 * self.rough(px / 2600 + 0.37, pz / 2600 - 1.9), 0.2, 1.25).astype(F32)
        if grad:
            hx = np.zeros(px.shape, F32)
            hz = np.zeros(px.shape, F32)
            occl = np.zeros(px.shape, F32)
        for k, (cell, amp) in enumerate(DOMES):
            bub = self.bub[k]
            gain = heap if k < 2 else (0.6 + 0.4 * heap) * (1 if k < 3 else knobs)
            att = np.clip(1.6 - 4.8 * fp / cell, 0, 1)
            if (which is not None and k not in which) or np.max(att) <= 0:
                h = h + amp * gain * bub.mean
                if grad:
                    occl += DEEP[k] * (1 - bub.mean)
                continue
            c, s = np.cos(self.turn[k]), np.sin(self.turn[k])
            u = (c * px - s * pz) / cell + self.shift[k, 0]
            v = (s * px + c * pz) / cell + self.shift[k, 1]
            if grad:
                b, crease, gu, gv = bub(u, v)
            else:
                b, crease = bub(u, v, grad=False)
            b = att * b + (1 - att) * bub.mean
            h = h + amp * gain * b
            if grad:
                soft = SOFT[k] * amp * gain * att / cell              # light diffuses over the smallest lobes
                hx += soft * (c * gu + s * gv)
                hz += soft * (-s * gu + c * gv)
                occl += DEEP[k] * (1 - b)
        if not grad:
            return h
        return h, hx, hz, occl


def ray_distances():
    """How far out each column's ray samples the cloud tops (m): about one sub-row apart as you look down,
    no more than 0.4% apart further out, to beyond the horizon."""
    step = PXR / SS
    d, out = 0.3, []
    while d < 330e3:
        out.append(d)
        d += min(step * (d * d + EYE_M ** 2) / EYE_M, max(0.004 * d, step * EYE_M))
    return np.array(out)


SUN_LIGHT = lin((255, 182, 104)) * 0.92           # the low sun, gold through the long air
SKY_ABOVE = lin((80, 104, 168)) * 0.22            # blue light from the sky overhead
SKY_SIDE = lin((122, 106, 152)) * 0.17            # lavender from the horizon's haze and the clouds round about
BOUNCE = lin((230, 156, 130)) * 0.08              # a warm return from the lit faces opposite


def shade(tops, px, pz, d, haze):
    """The colour of the cloud tops at (px, pz), seen from you, hazed by the air between; and the angle at which
    you see each point (degrees above level, so negative)."""
    drop = (d * d / (2 * R_EFF)).astype(F32)
    slant0 = np.sqrt(d * d + (EYE_M + drop) ** 2)
    fp = (slant0 * PXR).astype(F32)
    h, hx, hz, occl = tops(px, pz, fp)
    rel = h - EYE_M - drop
    ang = np.degrees(np.arctan2(rel, d)).astype(F32)
    dist = np.sqrt(d * d + rel * rel)
    vx, vy, vz = px / dist, rel / dist, pz / dist                       # the view ray, toward the point
    nn = 1 / np.sqrt(1 + hx * hx + hz * hz)
    nx, ny, nz = -hx * nn, nn, -hz * nn
    ndl = nx * SUN[0] + ny * SUN[1] + nz * SUN[2]
    ndv = -(nx * vx + ny * vy + nz * vz)                                # facing you
    vdl = vx * SUN[0] + vy * SUN[1] + vz * SUN[2]                       # looking toward the sun

    # Shadows: other domes between each point and the sun, felt for along the light.
    sx, sz = np.cos(np.radians(SUN_LON)), np.sin(np.radians(SUN_LON))
    tan_el = np.tan(np.radians(SUN_EL))
    occ = np.zeros(px.shape, F32)
    for r in PROBES:
        which = [k for k, (cell, _) in enumerate(DOMES) if cell >= r / 3]
        hq = tops(px + r * sx, pz + r * sz, fp, which, grad=False)
        occ = np.maximum(occ, smoothstep(0, 0.08 * r + 10, hq - h - r * tan_el))
    lit = 1 - occ

    ao = np.clip(np.exp(-0.55 * (occl - 2.2)), 0.3, 1.35).astype(F32)
    wrapd = np.clip((ndl + 0.2) / 1.2, 0, 1) ** 1.5
    turned = np.clip(-(nx * sx + nz * sz) / np.maximum(np.sqrt(nx * nx + nz * nz), 1e-4), 0, 1) * (1 - ny)
    g = 0.75
    hg = (1 - g * g) / (1 + g * g - 2 * g * vdl) ** 1.5 / 40
    rim = np.clip(1 - ndv, 0, 1) ** 5
    c = (SUN_LIGHT * (wrapd * lit)[..., None]
         + (SKY_ABOVE * (0.5 + 0.5 * ny)[..., None] + SKY_SIDE * (0.5 - 0.5 * ny)[..., None]) * ao[..., None]
         + BOUNCE * (turned * ao)[..., None]
         + SUN_LIGHT * (2.2 * rim * hg * (0.2 + 0.8 * lit))[..., None])
    # Mist settles in the hollows further off, and the air hazes everything toward the horizon's colour.
    mist = 0.55 * (1 - np.exp(-d / 9000)) * smoothstep(60, -260, h - 0)
    c = c + mist[..., None] * (haze * 0.95 - c)
    t = np.exp(-(dist / 80000) ** 1.15)[..., None]
    c = haze + t * (c - haze)
    return c.astype(F32), ang


def sea():
    """The cloud sea under the horizon: per column (2x across) a ray marched out over the cloud tops, front to back;
    each sub-row (2x down) shows the nearest top that rises into it. Returns the lower half of the picture."""
    tops = Tops()
    d = ray_distances()
    S, C = d.size, W * SS
    lon = np.radians(LON_SS)
    cl, sl = np.cos(lon).astype(F32), np.sin(lon).astype(F32)
    haze = sky_colour(cl, np.full(C, -0.004, F32), sl)[:, None, :]       # the horizon's haze, per column
    ang = np.empty((C, S), F32)
    col = np.empty((C, S, 3), F32)
    B = 64
    for s0 in range(0, S, B):
        dd = d[s0:s0 + B].astype(F32)[None, :]
        c, a = shade(tops, cl[:, None] * dd, sl[:, None] * dd, dd, haze)
        col[:, s0:s0 + B], ang[:, s0:s0 + B] = c, a
    top = np.maximum.accumulate(ang, axis=1)
    el = -(np.arange(HALF * SS) + 0.5) / SS * PX                        # sub-rows below the horizon
    out = np.empty((HALF, W, 3), F32)
    n = 512
    for c0 in range(0, C, n):
        key = (top[c0:c0 + n].astype(np.float64) + 1000.0 * np.arange(n)[:, None]).ravel()
        q = (el[None, :] + 1000.0 * np.arange(n)[:, None]).ravel()
        idx = np.searchsorted(key, q).reshape(n, -1) - S * np.arange(n)[:, None]
        hit = idx < S
        i = np.minimum(idx, S - 1)
        r = np.arange(c0, c0 + n)[:, None]
        sub = np.where(hit[..., None], col[r, i], 0)
        if not hit.all():
            x, y, z = direction(el[None, :], np.degrees(lon[c0:c0 + n])[:, None])
            sub = np.where(hit[..., None], sub, sky_colour(x, y, z))
        k = n // SS
        out[:, c0 // SS:c0 // SS + k] = sub.reshape(k, SS, HALF, SS, 3).mean((1, 3)).transpose(1, 0, 2)
    return out, top[:, -1]


# --- Output ----------------------------------------------------------------------------------

def encode(img):
    """sRGB with a fine grain that survives the JPEG, so the gradients don't band."""
    g = rng(9)
    grain = g.normal(0, 1, (H, W, 1)).astype(np.float32)
    grain = blur(grain, 0.55, 0.55)[..., 0]
    grain *= 0.8 / grain.std()
    knee = 0.8                                     # highlights roll off instead of clipping
    img = np.where(img > knee, knee + (1 - knee) * np.tanh((img - knee) / (1 - knee)), img)
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
    ih = img.shape[0]
    return bilinear(img.astype(np.float32), (90 - lat) / (180.0 / ih) - 0.5, lon / (180.0 / ih) - 0.5)


def previews(path, folder):
    os.makedirs(folder, exist_ok=True)
    img = np.asarray(Image.open(path).convert("RGB"))
    Image.fromarray(img).resize((2048, 1024), Image.LANCZOS).save(os.path.join(folder, "panorama.png"))
    views = {"forward": (SCREEN_LON, 0), "sun": (SUN_LON, 0), "away": (SUN_LON + 180, 0),
             "down30": (SCREEN_LON, -30), "down": (SCREEN_LON, -90), "up": (SCREEN_LON, 90), "seam": (0, 0),
             "sun_down30": (SUN_LON, -30), "away_down30": (SUN_LON + 180, -30)}
    for name, (yaw, pitch) in views.items():
        view = perspective(img, yaw, pitch)
        Image.fromarray(np.clip(view + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(folder, name + ".png"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?", default=OUT)
    ap.add_argument("--preview", metavar="DIR", help="also write a panorama and 90 degree views here")
    args = ap.parse_args()
    lower, edge = sea()
    pixels = encode(np.concatenate([sky(), lower]))
    Image.fromarray(pixels).save(args.out, quality=88, optimize=True)
    luma = (pixels.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255
    solid = np.cos(np.radians(90 - (np.arange(H) + 0.5) * PX))[:, None]
    print("clouds %s: %d KB, mean luminance %.1f%% (%.1f%% by solid angle), cloud horizon %.2f..%.2f deg" % (
        os.path.basename(args.out), os.path.getsize(args.out) // 1024, luma.mean() * 100,
        (luma * solid).sum() / (solid.sum() * W) * 100, edge.min(), edge.max()))
    if args.preview:
        previews(args.out, args.preview)


if __name__ == "__main__":
    main()
