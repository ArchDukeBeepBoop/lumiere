"""Lumiere's Moon: the lunar highlands at morning, 4096 x 2048 equirect, for a skybox on a Quest.

You stand in the lunar highlands at morning: grey regolith pocked with craters of every size and
strewn with boulders, worn massifs on the horizon, everything casting long black shadows from a sun 11
degrees up behind you to the right; the Earth, a little larger than life, hangs 23 degrees up to the
left of the screen, nearly full, blue and white; the black sky holds faint stars. The land is a height
field drawn 4x across, shaded Lambert with a share of Lommel-Seeliger and a phase law; the far ground
fades its detail below each pixel's footprint so the horizon doesn't shimmer.

    python3 moon.py [OUT.jpg] [--preview DIR]

writes OUT (by default the Quest's res/drawable-nodpi/lumiere_moon.jpg);
--preview also writes a small panorama and perspective views to DIR.
"""
import argparse
import os
import time
import numpy as np
from PIL import Image

W, H = 4096, 2048
HALF = H // 2                      # the horizon lies between rows HALF-1 and HALF
PX = 180.0 / H                     # degrees per pixel, down and across
PXR = np.pi / H                    # the same in radians
SS = 4                             # the land is drawn 4x across
LON = (np.arange(W) + 0.5) * PX
LON_SS = (np.arange(W * SS) + 0.5) * PX / SS
SCREEN_LON = 180.0                 # where the film's screen stands
SCREEN_M = 16.0                    # and how far off
SUN_LON, SUN_EL = 300.0, 11.0      # the morning Sun, behind you and to the right
EARTH_LON, EARTH_EL = 134.0, 23.0  # the Earth, up and to the left, clear of the screen
EARTH_DEG = 4.6                    # its diameter (truly 1.9 degrees)
EYE_M = 1.7                        # your eyes above the ground
R_MOON = 1737.4e3
SEED = 1969
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../quest/src/main/res/drawable-nodpi/lumiere_moon.jpg")


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


def unit(lon, el):
    """The direction at longitude lon, elevation el (degrees): x and z round the horizon, y up."""
    lo, la = np.radians(lon), np.radians(el)
    return np.array([np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)])


SUN = unit(SUN_LON, SUN_EL)
EARTH = unit(EARTH_LON, EARTH_EL)
SUN_C, SUN_S = np.cos(np.radians(SUN_EL)), np.sin(np.radians(SUN_EL))

# The ground plane's own axes: a toward the Sun's azimuth, b square to it (so shadows run along a).
SA = np.array([np.cos(np.radians(SUN_LON)), np.sin(np.radians(SUN_LON))])
SB = np.array([-SA[1], SA[0]])


def plane(lon, dist):
    """(a, b) of the point dist metres out at longitude lon."""
    lr = np.radians(lon)
    x, z = dist * np.cos(lr), dist * np.sin(lr)
    return x * SA[0] + z * SA[1], x * SB[0] + z * SB[1]


FOOT = plane(SCREEN_LON, SCREEN_M)


class Perlin:
    """2D gradient noise on a plane, roughly -1..1; grad() gives its gradient too."""

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
        """The noise alone, without its gradient (cheaper)."""
        xf, yf = np.floor(x), np.floor(y)
        fx, fy = (x - xf).astype(np.float32), (y - yf).astype(np.float32)
        xi, yi = xf.astype(np.int64) & 255, yf.astype(np.int64) & 255
        p, gx, gy = self.perm, self.gx, self.gy
        pa, pb = p[xi], p[xi + 1]
        h00, h10, h01, h11 = p[pa + yi], p[pb + yi], p[pa + yi + 1], p[pb + yi + 1]
        u, v = fx * fx * fx * (fx * (fx * 6 - 15) + 10), fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        n00, n10 = gx[h00] * fx + gy[h00] * fy, gx[h10] * (fx - 1) + gy[h10] * fy
        n01, n11 = gx[h01] * fx + gy[h01] * (fy - 1), gx[h11] * (fx - 1) + gy[h11] * (fy - 1)
        a, b = n00 + u * (n10 - n00), n01 + u * (n11 - n01)
        return 1.41 * (a + v * (b - a))


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


# --- The land: a height field round you, in nested grids -----------------------------------

N = 2048                                  # each grid's cells across
LEVELS = 16                               # 4 m across (2 mm cells) up to 131 km (64 m cells)
L0 = 4.0
REACH = 0.48 * L0 * 2 ** (LEVELS - 1)     # how far the land goes (63 km; the horizon is 2.4 km off)


def cell(k):
    return L0 * 2.0 ** k / N


def rough(lam):
    """How high the rolling ground rises at wavelength lam (m): self-similar, a little smoother when large."""
    return 0.012 * lam ** 0.95


# Massifs on the skyline: where (longitude, km off), how high (m), how wide (km), how long for its width
# and how its long axis is turned from square-on to you (degrees).
MASSIFS = [
    (127, 21, 1500, 5.5, 1.5, 20),        # under the Earth
    (147, 34, 1100, 6.0, 1.8, -10),
    (172, 42, 1500, 8.0, 2.0, 5),         # far and low, behind the screen
    (262, 25, 1100, 5.0, 1.6, 30),
    (291, 27, 2100, 7.0, 1.4, -15),       # under the Sun, lit from behind
    (318, 15, 650, 3.5, 1.5, 40),
    (20, 30, 1700, 6.5, 1.7, 0),
    (52, 38, 2300, 8.0, 1.5, -25),
    (95, 26, 1200, 5.0, 2.2, 10),
]
# Great craters whose near rims stand on the skyline: longitude, km to the centre, diameter km, rim m.
BIG_CRATERS = [
    (222, 36, 30, 950),                   # a long wall forward and right
    (350, 30, 22, 800),                   # behind you
    (78, 40, 26, 900),
]


def _cr(t):
    return np.array([(-t ** 3 + 2 * t * t - t) / 2, (3 * t ** 3 - 5 * t * t + 2) / 2,
                     (-3 * t ** 3 + 4 * t * t + t) / 2, (t ** 3 - t * t) / 2], np.float32)


CR_EVEN, CR_ODD = _cr(0.75), _cr(0.25)


def upsample(c):
    """A coarser grid's middle half at twice its resolution (Catmull-Rom, so slopes stay smooth)."""
    q, P = N // 4, N // 2

    def along(x):
        out = np.empty((2 * P,) + x.shape[1:], np.float32)
        out[0::2] = sum(w * x[q - 2 + m:q - 2 + m + P] for m, w in enumerate(CR_EVEN))
        out[1::2] = sum(w * x[q - 1 + m:q - 1 + m + P] for m, w in enumerate(CR_ODD))
        return out

    return np.ascontiguousarray(along(along(c.astype(np.float32)).T).T)


def octave(noise, A, B, lam, k, salt):
    """One octave of noise at wavelength lam over the grid, turned and shifted per level."""
    th = 0.7 * k + 1.3 * salt
    c, s = np.cos(th), np.sin(th)
    return noise((c * A - s * B) / lam + 17.1 * salt + 3.3 * k, (s * A + c * B) / lam - 9.7 * salt + 5.1 * k)


def patches(k, ca, cb, rad, batch=3000):
    """For features centred at (ca, cb) metres: each one's square of cells, rad cells either side, as offsets
    from its centre (m), which cells lie on the grid, and their flat indices."""
    c = cell(k)
    off = np.arange(-rad, rad + 1)
    ic = np.round(ca / c + N / 2 - 0.5).astype(np.int64)
    jc = np.round(cb / c + N / 2 - 0.5).astype(np.int64)
    for s in range(0, ca.size, batch):
        sl = slice(s, s + batch)
        ii = ic[sl, None, None] + off[None, :, None]
        jj = jc[sl, None, None] + off[None, None, :]
        da = ((ii - (N / 2 - 0.5)) * c - ca[sl, None, None]).astype(np.float32)
        db = ((jj - (N / 2 - 0.5)) * c - cb[sl, None, None]).astype(np.float32)
        ok = (ii >= 0) & (ii < N) & (jj >= 0) & (jj < N)
        yield sl, da, db, ok, ii * N + jj


def add(grid, flat, ok, vals):
    grid.reshape(-1)[:] += np.bincount(flat[ok], np.broadcast_to(vals, ok.shape)[ok], N * N).astype(np.float32)


def crater_shape(r, f):
    """A simple crater's height, in diameters, r radii from its centre; f is how fresh it is (0 worn, 1 new):
    fresh ones are deep bowls with sharp raised rims, worn ones shallow dishes with soft lips."""
    depth = 0.04 + 0.16 * f
    rim = 0.008 + 0.034 * f
    dish = np.clip(1 - r * r, 0, 1) ** (1 + 2 * (1 - f))
    inner = np.exp(-((r - 1) / (0.2 + 0.25 * (1 - f))) ** 2)
    outer = np.clip(2 - r, 0, 1) ** 2 / np.maximum(r, 1) ** 2
    return rim * np.where(r < 1, inner, outer) - depth * dish


def craters(k, h, B, T, g, D0, prob):
    """Craters D0..2 D0 across, at most one in each square 2 D0 on a side."""
    c = cell(k)
    C = 2 * D0
    n = int(N * c / 2 / C) + 2
    I = np.arange(-n, n)
    gi, gj = np.meshgrid(I, I, indexing="ij")
    u = g.random((5,) + gi.shape)
    sel = u[0] < prob
    ca, cb = (gi[sel] + u[1][sel]) * C, (gj[sel] + u[2][sel]) * C
    D = D0 * 2 ** u[3][sel]
    f = u[4][sel] ** 2.5
    # The ground under your feet and under the screen's foot stays whole.
    near = (np.hypot(ca, cb) < 0.6 * D + 3) & (D > 1.5)
    foot = (np.hypot(ca - FOOT[0], cb - FOOT[1]) < 0.6 * D + 6) & (D > 3)
    keep = ~(near | foot)
    ca, cb, D, f = ca[keep], cb[keep], D[keep], f[keep]
    rad = int(np.ceil(2 * D0 / c)) + 1
    for sl, da, db, ok, flat in patches(k, ca, cb, rad):
        Dd = D[sl, None, None].astype(np.float32)
        r = np.sqrt(da * da + db * db) / (Dd / 2)
        add(h, flat, ok & (r < 2), Dd * crater_shape(r, f[sl, None, None].astype(np.float32)))
    # Fresh ones threw out bright, unweathered rock: a paler, cooler halo round them.
    fresh = f > 0.3
    ca, cb, D, f = ca[fresh], cb[fresh], D[fresh], f[fresh]
    w = ((f - 0.3) / 0.7).astype(np.float32)
    rad = int(np.ceil(3 * D0 / c)) + 1
    for sl, da, db, ok, flat in patches(k, ca, cb, rad):
        r = np.sqrt(da * da + db * db) / (D[sl, None, None].astype(np.float32) / 2)
        halo = w[sl, None, None] * np.exp(-(r / 1.7) ** 2)
        add(B, flat, ok & (r < 3), 0.45 * halo)
        add(T, flat, ok & (r < 3), -0.8 * halo)


def boulders(k, h, B, T, rock, g, D0, prob, field):
    """Rocks D0..2 D0 across, gathered into fields: rounded, with a few flat faces, sat in the regolith."""
    c = cell(k)
    C = 2 * D0
    n = int(N * c / 2 / C) + 2
    I = np.arange(-n, n)
    gi, gj = np.meshgrid(I, I, indexing="ij")
    u = g.random((12,) + gi.shape)
    ca0, cb0 = (gi + u[1]) * C, (gj + u[2]) * C
    gather_ = 0.15 + 2.2 * smoothstep(-0.1, 0.6, field(ca0 / (60 * D0) + 0.37, cb0 / (60 * D0) - 0.61))
    sel = u[0] < prob * gather_
    ca, cb = ca0[sel], cb0[sel]
    D = D0 * 2 ** u[3][sel]
    keep = ~(((np.hypot(ca, cb) < 3.5) & (D > 0.12)) | ((np.hypot(ca - FOOT[0], cb - FOOT[1]) < 7) & (D > 0.4)))
    v = [x[sel][keep].astype(np.float32) for x in u[4:]]
    ca, cb, D = ca[keep], cb[keep], D[keep].astype(np.float32)
    R = D / 2
    tall = R * (0.5 + 0.45 * v[0])
    rad = int(np.ceil(1.45 * D0 / c)) + 1
    for sl, da, db, ok, flat in patches(k, ca, cb, rad):
        Rr, Ht = R[sl, None, None], tall[sl, None, None]
        p = [x[sl, None, None] for x in v]
        phi = np.arctan2(db, da)
        Rphi = Rr * (1 + (0.1 + 0.15 * p[1]) * np.cos(2 * (phi - 6.28 * p[2])) + 0.1 * p[3] * np.cos(3 * (phi - 6.28 * p[4])))
        s = np.sqrt(da * da + db * db) / Rphi
        shape = np.sqrt(np.clip(1 - s * s, 0, 1))
        for m in range(2):               # two flat faces cut across it
            ang = 6.28 * p[5 + m]
            cut = 0.8 + 0.2 * p[1 + m] - (da * np.cos(ang) + db * np.sin(ang)) / Rr * (0.35 + 0.4 * p[3 + m])
            shape = np.minimum(shape, np.maximum(cut, 0))
        inside = ok & (s < 1.05)
        add(h, flat, inside, Ht * shape)
        mask = smoothstep(1.05, 0.85, s)
        add(rock, flat, inside, mask)
        add(B, flat, inside, mask * (0.35 * p[6] - 0.05))
        add(T, flat, inside, mask * -0.35)


def massifs(A, B, noise):
    h = np.zeros(np.broadcast_shapes(A.shape, B.shape), np.float32)
    for lon, km, rise, wide, longer, turn in MASSIFS:
        ma, mb = plane(lon, km * 1000)
        th = np.radians(lon + 90 + turn - SUN_LON)
        da, db = A - ma, B - mb
        u = (da * np.cos(th) + db * np.sin(th)) / (wide * 1000 * longer)
        v = (-da * np.sin(th) + db * np.cos(th)) / (wide * 1000)
        r2 = (u * u + v * v).astype(np.float32)
        h += rise * (0.55 * np.exp(-r2) + 0.45 * np.exp(-1.7 * np.sqrt(r2)))
    lumpy = 0.8 + 0.35 * noise(A / 9000.0 + 3.1, B / 9000.0 - 1.7)
    return h * lumpy


def big_crater(r, rim):
    """A complex crater's height (m): a flat floor with a central peak, terraced walls, a sharp rim, and
    an apron of ejecta falling away outside."""
    depth = 2.4 * rim
    wall = smoothstep(0.55, 1.0, r)
    terr = 0.04 * np.sin(np.clip(r - 0.55, 0, 0.45) / 0.45 * np.pi * 4)
    peak = 0.45 * depth * np.exp(-(r / 0.13) ** 2)
    inside = -depth + (depth + rim) * (wall ** 1.6 + terr * wall * (1 - wall) * 4) + peak
    outside = rim / np.maximum(r, 1) ** 3 * np.clip((3 - r) / 2, 0, 1) ** 2
    return np.where(r < 1, inside, outside)


def build_land():
    """Every grid from the coarsest in, each the next one's middle half at twice its detail plus its own
    octave of everything, its slopes, and which cells the Sun reaches."""
    noises = [Perlin(rng(10 + i)) for i in range(6)]
    field = Perlin(rng(20))
    hmap = np.empty((LEVELS, N, N), np.float32)
    ga = np.empty((LEVELS, N, N), np.float16)
    gb = np.empty((LEVELS, N, N), np.float16)
    lit = np.empty((LEVELS, N, N), np.float16)
    bright = np.empty((LEVELS, N, N), np.float16)
    tint = np.empty((LEVELS, N, N), np.float16)
    els = SUN_EL + np.linspace(-0.22, 0.22, 5)         # across the Sun's disc, for soft shadows
    incoming = None
    prev = None
    for k in reversed(range(LEVELS)):
        c = cell(k)
        ax = (np.arange(N) - N / 2 + 0.5) * c
        A, Bc = ax[:, None], ax[None, :]
        g = rng(100 + k)
        if prev is None:
            h = massifs(A, Bc, noises[5])
            for lon, km, dia, rim in BIG_CRATERS:
                ma, mb = plane(lon, km * 1000)
                r = (np.hypot(A - ma, Bc - mb) / (dia * 500)).astype(np.float32)
                h += big_crater(r, rim).astype(np.float32)
            B = np.ones((N, N), np.float32)
            T = np.zeros((N, N), np.float32)
            rock = np.zeros((N, N), np.float32)
            lams = [8 * c * 2 ** m for m in range(8)]
            sizes = [4 * c * 2 ** m for m in range(4)]
            # The land's broad paler and darker tracts, warmer and cooler.
            for m, lam in enumerate([12000.0, 5000.0, 2000.0, 800.0]):
                B += (0.07 if m < 2 else 0.04) * octave(noises[m % 6], A, Bc, lam, k, 7 + m)
                T += (0.45 if m < 2 else 0.2) * octave(noises[(m + 2) % 6], A, Bc, lam * 1.3, k, 11 + m)
        else:
            h, B, T, rock = (upsample(x) for x in prev)
            rock = np.clip(rock, 0, 1)
            lams = [8 * c]
            sizes = [4 * c]
            B += 0.03 * octave(noises[k % 6], A, Bc, 12 * c, k, 5)
            if k > 6:
                T += 0.06 * octave(noises[(k + 1) % 6], A, Bc, 14 * c, k, 6)
            # Rock faces keep their roughness and speckle all the way down.
            if rock.max() > 0:
                rough_rock = octave(noises[(k + 3) % 6], A, Bc, 5 * c, k, 4)
                h += rock * (0.05 * 5 * c) * rough_rock
                B += rock * 0.06 * rough_rock
        for m, lam in enumerate(lams):
            h += rough(lam) * octave(noises[(k + m) % 6], A, Bc, lam, k, m)
        for D0 in sizes:
            craters(k, h, B, T, g, D0, 0.32)
        if 4 * c <= 2.5:
            boulders(k, h, B, T, rock, g, 4 * c, min(0.5, 0.006 * (4 * c) ** -0.5), field)
        prev = (h, B, T, rock)
        hmap[k] = h
        dh = np.gradient(h, c)
        ga[k], gb[k] = dh[0], dh[1]
        # Shadows: a cell is in shadow if anything between it and the Sun, along its row, rises above the
        # line to the Sun: with g = h - a tan(el), if any cell sunward has a higher g. Rows enter from the
        # coarser grid with the highest g beyond this grid's sunward edge.
        h64 = h.astype(np.float64)
        sun_lit = np.zeros((N, N), np.float32)
        nxt = []
        for e, el in enumerate(els):
            gg = h64 - A * np.tan(np.radians(el))
            best = np.maximum.accumulate(gg[::-1], axis=0)[::-1]
            beyond = np.full(N, -np.inf) if incoming is None else incoming[e]
            best = np.maximum(best, beyond[None, :])
            ahead = np.empty_like(best)
            ahead[:-1] = best[1:]
            ahead[-1] = beyond
            sun_lit += ahead <= gg + 1e-5 * c
            jj = np.arange(N) / 2 + N / 4 - 0.25
            nxt.append(np.interp(jj, np.arange(N), best[3 * N // 4]))
        incoming = nxt
        lit[k] = sun_lit / len(els)
        bright[k], tint[k] = B, T
        print("  grid %2d: %8.3f m cells, heights %.1f..%.1f m" % (k, c, h.min(), h.max()), flush=True)
    return hmap, ga, gb, lit, bright, tint


def level_of(t):
    """The grid for ground t metres off, and how far toward the next coarser one to blend."""
    u = np.log2(np.maximum(t, 1e-6) / (0.36 * L0))
    k0 = np.clip(np.floor(u), 0, LEVELS - 1)
    w = smoothstep(0, 0.415, u - k0) * (k0 < LEVELS - 1)
    return k0.astype(np.int64), w.astype(np.float32)


def gather(maps, k, a, b):
    """Bilinear samples of each (LEVELS, N, N) map in grid k at plane points (a, b)."""
    c = (L0 / N) * np.exp2(k.astype(np.float64))
    fi = a / c + (N / 2 - 0.5)
    fj = b / c + (N / 2 - 0.5)
    i0 = np.clip(np.floor(fi), 0, N - 2)
    j0 = np.clip(np.floor(fj), 0, N - 2)
    ti = np.clip(fi - i0, 0, 1).astype(np.float32)
    tj = np.clip(fj - j0, 0, 1).astype(np.float32)
    base = (k.astype(np.int64) * N + i0.astype(np.int64)) * N + j0.astype(np.int64)
    out = []
    for m in maps:
        f = m.reshape(-1)
        v00, v01 = f[base].astype(np.float32), f[base + 1].astype(np.float32)
        v10, v11 = f[base + N].astype(np.float32), f[base + N + 1].astype(np.float32)
        top = v00 + tj * (v01 - v00)
        out.append(top + ti * (v10 + tj * (v11 - v10) - top))
    return out


def sample(maps, t, a, b):
    """The maps at ground t metres off, blended between grids so no ring shows where one hands over."""
    k0, w = level_of(t)
    v0 = gather(maps, k0, a, b)
    v1 = gather(maps, np.minimum(k0 + 1, LEVELS - 1), a, b)
    return [x + w * (y - x) for x, y in zip(v0, v1)]


# --- Light on the regolith -------------------------------------------------------------------

LS_SHARE = 0.35                            # how much Lommel-Seeliger (the Moon's flat-disc look) to Lambert
EXPOSURE = 0.62
FILL = 0.016                               # light in the shadows, from sunlit ground round about
FILL_COL = np.array([0.95, 0.99, 1.07], np.float32)
TINT0 = np.array([1.04, 0.995, 0.92], np.float32)     # mature regolith: grey with a little brown in it
TINT_D = np.array([0.05, 0.0, -0.075], np.float32)    # warmer for +, cooler (fresher) for -
KNEE, WHITE = 0.26, 0.56                   # a soft shoulder, so no sunlit face nears the film's whites
GRAIN = [(0.0052, 0.10, 0.22), (0.0094, 0.07, 0.16)]  # the regolith's own grain at your feet: wavelength
                                                      # (m), albedo and slope amounts


def regolith(cos_i, cos_e, cos_a):
    """How bright the regolith looks for incidence, emission and phase: Lambert with a share of
    Lommel-Seeliger, times a phase law that dims toward the Sun and brightens away from it."""
    ci = np.maximum(cos_i, 0)
    ce = np.maximum(cos_e, 0.04)
    ls = 2 * ci / (ci + ce)
    alpha = np.degrees(np.arccos(np.clip(cos_a, -1, 1)))
    phase = 0.55 + 0.45 * np.exp(-alpha / 45) + 0.25 * np.exp(-alpha / 7)
    return (LS_SHARE * ls + (1 - LS_SHARE) * ci) * phase


def tone(x):
    """Linear below the knee, then a shoulder that never passes WHITE."""
    return np.where(x < KNEE, x, KNEE + (WHITE - KNEE) * (1 - np.exp(-(x - KNEE) / (WHITE - KNEE))))


def shade(land, grain, t, a, b, va, vy, vb):
    """The colour of the ground at plane point (a, b), t metres off, seen along (va, vy, vb)."""
    ga, gb, lit, bright, tint = sample(land[1:], t, a, b)
    foot = np.maximum(PXR * np.sqrt(t * (t * t + EYE_M ** 2) / EYE_M), PXR * EYE_M)
    for (lam, amp, slope), noise in zip(GRAIN, grain):
        att = np.clip(1.6 - 2.4 * foot / lam, 0, 1)
        if att.max() <= 0:
            continue
        n, dx, dy = noise.grad(a / lam + 11.3, b / lam - 7.7)
        bright = bright * (1 + amp * att * n)
        ga = ga + slope * att * dx
        gb = gb + slope * att * dy
    nrm = 1 / np.sqrt(1 + ga * ga + gb * gb)
    cos_i = (SUN_S - ga * SUN_C) * nrm
    cos_e = (ga * va + gb * vb - vy) * nrm
    cos_a = -(va * SUN_C + vy * SUN_S)
    light = regolith(cos_i, cos_e, cos_a) * lit
    steep = smoothstep(0.35, 0.9, np.sqrt(ga * ga + gb * gb))      # fresh rock shows on steep slopes
    col = (TINT0 + tint[..., None] * TINT_D) * (bright * (1 + 0.2 * steep))[..., None]
    return EXPOSURE * col * (light[..., None] + FILL * FILL_COL)


T0, STEP = 0.02, 1.006
TS = T0 * STEP ** np.arange(int(np.log(REACH / T0) / np.log(STEP)) + 1)
BAND_UP = 6.0                              # degrees above the horizon that land may rise to


def render_ground(land):
    """Per column (4x across), a ray marched out over the land front to back; each sub-row shows the
    nearest ground that rises into it. Returns the rows from BAND_UP down, and the land's coverage."""
    hmap = land[0]
    grain = [Perlin(rng(30 + i)) for i in range(len(GRAIN))]
    eye = float(gather([hmap], np.zeros(1, np.int64), np.zeros(1), np.zeros(1))[0][0]) + EYE_M
    S = TS.size
    drop = TS ** 2 / (2 * R_MOON)
    top_row = HALF - int(round(BAND_UP / PX))
    quarter = (0.125, 0.375, 0.625, 0.875)
    regions = [  # rows, and the sub-rows for the even and odd sub-columns: more samples near the horizon
        (top_row, HALF + int(round(6 / PX)), quarter, quarter),
        (HALF + int(round(6 / PX)), HALF + int(round(25 / PX)), (0.125, 0.625), (0.375, 0.875)),
        (HALF + int(round(25 / PX)), H, (0.25,), (0.75,)),
    ]
    out = np.zeros((H - top_row, W, 3), np.float32)
    cover = np.zeros((H - top_row, W), np.float32)
    CH = 512
    highest = -90.0
    for c0 in range(0, W * SS, CH):
        lr = np.radians(LON_SS[c0:c0 + CH])
        ca = np.cos(lr) * SA[0] + np.sin(lr) * SA[1]
        cb = np.cos(lr) * SB[0] + np.sin(lr) * SB[1]
        A, B = ca[:, None] * TS[None, :], cb[:, None] * TS[None, :]
        tt = np.broadcast_to(TS[None, :], A.shape)
        hh = sample([hmap], tt, A, B)[0]
        ang = np.degrees(np.arctan2(hh - eye - drop[None, :], TS[None, :])).astype(np.float64)
        top = np.maximum.accumulate(ang, axis=1)
        highest = max(highest, float(top[:, -1].max()))
        p0 = c0 // SS
        for r0, r1, f0, f1 in regions:
            for par, fr in ((0, f0), (1, f1)):
                cols = np.arange(par, CH, 2)
                rows = np.arange(r0, r1)
                el = (90 - (rows[:, None] + np.array(fr)[None, :]) * PX).ravel()
                n, m = cols.size, el.size
                key = (top[cols] + 1000.0 * np.arange(n)[:, None]).ravel()
                q = (el[None, :] + 1000.0 * np.arange(n)[:, None]).ravel()
                idx = np.searchsorted(key, q).reshape(n, m) - S * np.arange(n)[:, None]
                hit = idx < S
                j = np.clip(idx, 1, S - 1)
                rr = cols[:, None]
                a0, a1 = ang[rr, j - 1], ang[rr, j]
                f = np.clip((el[None, :] - a0) / np.maximum(a1 - a0, 1e-9), 0, 1)
                t = TS[j - 1] + f * (TS[j] - TS[j - 1])
                under = (eye - hh[cols, 0])[:, None] / np.tan(np.radians(np.maximum(-el, 1e-3)))[None, :]
                t = np.where(idx == 0, under, t)
                sel = hit
                col = np.zeros((n, m, 3), np.float32)
                if sel.any():
                    ts = t[sel]
                    cae, cbe = np.broadcast_to(ca[cols][:, None], (n, m))[sel], np.broadcast_to(cb[cols][:, None], (n, m))[sel]
                    elr = np.radians(np.broadcast_to(el[None, :], (n, m))[sel])
                    ce = np.cos(elr)
                    rgb = shade(land, grain, ts, ts * cae, ts * cbe, ce * cae, np.sin(elr), ce * cbe)
                    col[sel] = tone(rgb)
                nf = len(fr)
                part = col.reshape(n // 2, 2, r1 - r0, nf, 3).sum((1, 3)) / (4 * nf)
                out[r0 - top_row:r1 - top_row, p0:p0 + CH // SS] += part.transpose(1, 0, 2)
                cov = hit.reshape(n // 2, 2, r1 - r0, nf).sum((1, 3)) / (4 * nf)
                cover[r0 - top_row:r1 - top_row, p0:p0 + CH // SS] += cov.T
    print("  land rises to %.2f degrees" % highest)
    return out, cover, top_row


# --- The sky -----------------------------------------------------------------------------------

def stars(img):
    """A few faint stars, round on the sphere; the exposure for the sunlit ground hides the rest."""
    g = rng(4)
    count = 1400
    lat = np.degrees(np.arcsin(g.uniform(np.sin(np.radians(1)), 1, count)))     # even over the sky
    lon = g.uniform(0, 360, count)
    mag = g.pareto(1.8, count) + 1
    hot = g.random(count)
    sigma = 0.06
    shown = 0
    for la, lo, m, t in zip(lat, lon, mag, hot):
        b = min(0.0028 * m ** 1.5, 0.07)
        if b < 0.006:
            continue
        shown += 1
        row, col = (90 - la) / PX - 0.5, lo / PX - 0.5
        cosl = max(np.cos(np.radians(la)), 0.03)
        r0, r1 = max(int(row) - 3, 0), min(int(row) + 5, HALF)
        span = min(int(3 / cosl) + 2, W // 2)
        cols = np.arange(int(col) - span, int(col) + span + 1)
        dy = (np.arange(r0, r1)[:, None] - row) * PX
        dx = wrap((cols[None, :] - col) * PX) * cosl
        spot = b * np.exp(-(dy * dy + dx * dx) / (2 * sigma ** 2))
        tint = np.interp(t, [0, 0.2, 0.7, 1], [0, 0.3, 0.6, 1])
        rgb = np.array([0.78 + 0.22 * tint, 0.86 + 0.08 * tint, 1.0 - 0.3 * tint], np.float32)
        img[r0:r1, cols % W] += spot[..., None] * rgb
    return shown


def waves(q, g, kmin, kmax, count, beta):
    """Noise on the sphere (q: unit vectors, shape (3, ...)): random plane waves, unit spread."""
    w = g.normal(size=(count, 3))
    w /= np.linalg.norm(w, axis=1, keepdims=True)
    k = kmin * (kmax / kmin) ** g.random(count)
    amp = k ** -beta
    ph = g.uniform(0, 2 * np.pi, count)
    s = np.zeros(q.shape[1:], np.float64)
    for wi, ki, ai, pi in zip(w, k, amp, ph):
        s += ai * np.sin(ki * (wi[0] * q[0] + wi[1] * q[1] + wi[2] * q[2]) + pi)
    return s / np.sqrt((amp ** 2).sum() / 2)


def rotate(q, axis, ang):
    """Turns unit vectors q (3, ...) about axis by ang (radians, per point)."""
    c, s = np.cos(ang), np.sin(ang)
    d = axis[0] * q[0] + axis[1] * q[1] + axis[2] * q[2]
    cr = np.stack([axis[1] * q[2] - axis[2] * q[1], axis[2] * q[0] - axis[0] * q[2], axis[0] * q[1] - axis[1] * q[0]])
    return q * c + cr * s + axis[:, None, None] * d * (1 - c)


def earth(img):
    """The Earth, gibbous, lit from the same Sun: oceans, a little land, cloud, a thin blue limb."""
    g = rng(7)
    rad = np.radians(EARTH_DEG / 2)
    up = np.array([0.0, 1.0, 0.0]) - EARTH[1] * EARTH
    up /= np.linalg.norm(up)
    right = np.array([-np.sin(np.radians(EARTH_LON)), 0.0, np.cos(np.radians(EARTH_LON))])
    tilt, lean = np.radians(-24), np.radians(18)
    pole = np.cos(lean) * (np.cos(tilt) * up + np.sin(tilt) * right) - np.sin(lean) * EARTH
    pole /= np.linalg.norm(pole)
    e1 = -EARTH - np.dot(-EARTH, pole) * pole
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(pole, e1)

    ext = 1.25 * EARTH_DEG / 2
    r0, r1 = int(np.floor((90 - EARTH_EL - ext) / PX)), int(np.ceil((90 - EARTH_EL + ext) / PX))
    wdeg = ext / np.cos(np.radians(EARTH_EL + ext))
    c0, c1 = int(np.floor((EARTH_LON - wdeg) / PX)), int(np.ceil((EARTH_LON + wdeg) / PX))
    S = 6
    rows = r0 + (np.arange((r1 - r0) * S) + 0.5) / S
    cols = c0 + (np.arange((c1 - c0) * S) + 0.5) / S
    d = unit(cols[None, :] * PX, 90 - rows[:, None] * PX)
    cos_t = np.tensordot(EARTH, d, 1)
    rho = np.arccos(np.clip(cos_t, -1, 1)) / rad
    tang = d - cos_t * EARTH[:, None, None]
    tang /= np.maximum(np.linalg.norm(tang, axis=0), 1e-12)
    rc = np.minimum(rho, 1)
    mu = np.sqrt(1 - rc * rc)
    n = -mu * EARTH[:, None, None] + rc * tang
    cos_i = np.tensordot(SUN, n, 1)

    # Where on the Earth each point is: q in the Earth's own frame.
    q = np.stack([np.tensordot(e1, n, 1), np.tensordot(e2, n, 1), np.tensordot(pole, n, 1)])
    spin = np.radians(35)
    q = np.stack([q[0] * np.cos(spin) - q[1] * np.sin(spin), q[0] * np.sin(spin) + q[1] * np.cos(spin), q[2]])
    lat = np.degrees(np.arcsin(np.clip(q[2], -1, 1)))

    cont = waves(q, g, 1.6, 9.0, 160, 1.1)
    land = smoothstep(0.42, 0.62, cont)
    arid = np.clip(np.exp(-((np.abs(lat) - 24) / 11) ** 2) + 0.35 * waves(q, g, 4, 14, 60, 1.0), 0, 1)
    ground = lin((66, 92, 50)) + arid[..., None] * (lin((190, 156, 112)) - lin((66, 92, 50)))
    ground = ground + smoothstep(50, 65, np.abs(lat))[..., None] * (lin((118, 108, 92)) - ground)
    ocean = lin((7, 24, 66)) + 0.4 * smoothstep(0.25, 0.42, cont)[..., None] * (lin((14, 52, 96)) - lin((7, 24, 66)))
    surf = ocean + land[..., None] * (ground - ocean)
    ice = smoothstep(68, 74, np.abs(lat) + 4 * waves(q, g, 5, 20, 40, 1.0))
    surf = surf + ice[..., None] * (lin((232, 238, 244)) - surf)

    # Cloud: zonal streaks, wound into a few storms, heavy over the storm tracks and thin over the deserts.
    qc = q * np.array([1.0, 1.0, 1.7])[:, None, None]
    for m in range(5):
        cl = np.radians(g.uniform(30, 58) * (1 if m % 2 else -1))
        clo = g.uniform(0, 2 * np.pi)
        axis = np.array([np.cos(cl) * np.cos(clo), np.cos(cl) * np.sin(clo), np.sin(cl)])
        dist = np.arccos(np.clip(np.tensordot(axis, q, 1), -1, 1))
        qc = rotate(qc, axis, 2.6 * np.sign(cl) * np.exp(-(dist / 0.24) ** 2))
    warp = np.stack([waves(q, g, 2, 6, 30, 1.0) for _ in range(3)])
    nc = waves(qc + 0.12 * warp, g, 3.0, 48.0, 360, 0.8)
    belt = 0.55 * np.exp(-(lat / 7) ** 2) + 0.5 * np.exp(-((np.abs(lat) - 52) / 13) ** 2) \
        - 0.45 * np.exp(-((np.abs(lat) - 24) / 9) ** 2)
    cloud = smoothstep(0.05, 1.0, nc + belt) ** 0.9
    surf = surf + (0.92 * cloud)[..., None] * (lin((246, 248, 252)) - surf)

    light = np.clip((cos_i + 0.04) / 1.04, 0, 1)
    half = SUN - EARTH
    half /= np.linalg.norm(half)
    glint = np.clip(np.tensordot(half, n, 1), 0, 1) ** 300 * (1 - land) * (1 - cloud) * 0.35
    sky_blue = np.array([0.07, 0.16, 0.48], np.float32)
    haze = sky_blue * (light * (0.16 + 0.85 * (1 - mu) ** 2.5))[..., None]
    rgb = 0.72 * (surf * light[..., None] + haze) + glint[..., None]
    disc = (rho < 1).astype(np.float32)
    limb = np.exp(-np.maximum(rho - 1, 0) / 0.016) * (rho >= 1) * smoothstep(-0.3, 0.35, np.tensordot(SUN, tang, 1))
    ring = sky_blue * 1.4 * limb[..., None]
    k = (r1 - r0, S, c1 - c0, S)
    rgb = (rgb * disc[..., None] + ring).reshape(k + (3,)).mean((1, 3))
    cov = disc.reshape(k).mean((1, 3))
    cc = np.arange(c0, c1) % W
    img[r0:r1, cc] = img[r0:r1, cc] * (1 - cov[..., None]) + rgb
    return np.degrees(np.arccos(np.clip(-np.dot(SUN, EARTH), -1, 1)))      # its phase angle


def sun_and_glare(img):
    """The Sun's disc, and a camera's glare round it, laid over everything (in display light)."""
    span = 40.0
    r0, r1 = max(int((90 - SUN_EL - span) / PX), 0), min(int((90 - SUN_EL + span) / PX), H)
    lat = 90 - (np.arange(r0, r1) + 0.5) * PX
    d = unit(LON[None, :], lat[:, None])
    th = np.degrees(np.arccos(np.clip(np.tensordot(SUN, d, 1), -1, 1)))
    glare = 0.3 * np.exp(-th / 0.35) + 0.045 * np.exp(-th / 1.8) + 0.011 * np.exp(-th / 8)
    warm = np.array([1.0, 0.95, 0.86], np.float32)
    img[r0:r1] += glare[..., None] * warm
    # The disc itself, 0.53 degrees, antialiased by 8x8 sub-samples over its own few pixels.
    rs, cs = int((90 - SUN_EL - 1) / PX), int((SUN_LON - 1.2) / PX)
    S = 8
    rr = rs + (np.arange(int(2 / PX) * S) + 0.5) / S
    cc = cs + (np.arange(int(2.4 / PX) * S) + 0.5) / S
    dd = unit(cc[None, :] * PX, 90 - rr[:, None] * PX)
    th = np.degrees(np.arccos(np.clip(np.tensordot(SUN, dd, 1), -1, 1)))
    cov = (th < 0.265).astype(np.float32).reshape(len(rr) // S, S, len(cc) // S, S).mean((1, 3))
    blk = img[rs:rs + cov.shape[0], cs:cs + cov.shape[1]]
    img[rs:rs + cov.shape[0], cs:cs + cov.shape[1]] = blk * (1 - cov[..., None]) + cov[..., None] * np.array([1.0, 0.99, 0.97])
    return img


# --- Output ----------------------------------------------------------------------------------

def encode(img):
    """sRGB with a fine grain that survives the JPEG, so the glare's and the Earth's gradients don't band;
    none on the black sky, which stays clean."""
    g = rng(9)
    grain = g.normal(0, 1, (H, W, 1)).astype(np.float32)
    grain = blur(grain, 0.55, 0.55)[..., 0]
    grain *= 0.8 / grain.std()
    s = srgb(img) * 255
    s += (grain * smoothstep(0.3, 3.0, s.max(-1)))[..., None]
    return np.clip(np.round(s), 0, 255).astype(np.uint8)


def perspective(img, yaw, pitch, fov=90, w=1280, h=720):
    """A view from inside the sphere, as you'd see it in the headset."""
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
    views = {"forward": (SCREEN_LON, -4, 90), "earth": (EARTH_LON, 12, 90), "sun": (SUN_LON, 2, 90),
             "down30": (SCREEN_LON, -30, 90), "up": (SCREEN_LON, 90, 90), "down": (SCREEN_LON, -90, 90),
             "seam": (0, -4, 90), "earth_zoom": (EARTH_LON, EARTH_EL, 12), "horizon_zoom": (215, 1, 30)}
    for name, (yaw, pitch, fov) in views.items():
        view = perspective(img, yaw, pitch, fov)
        Image.fromarray(np.clip(view + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(folder, name + ".png"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?", default=OUT)
    ap.add_argument("--preview", metavar="DIR", help="also write a panorama and perspective views here")
    args = ap.parse_args()
    t0 = time.time()
    img = np.zeros((H, W, 3), np.float32)
    shown = stars(img)
    phase = earth(img)
    print("sky: %d stars; the Earth at phase %.0f degrees, %.0f%% lit (%.1fs)" % (
        shown, phase, 50 * (1 + np.cos(np.radians(phase))), time.time() - t0), flush=True)
    land = build_land()
    print("land built (%.1fs)" % (time.time() - t0), flush=True)
    ground, cover, top_row = render_ground(land)
    del land
    print("land drawn (%.1fs)" % (time.time() - t0), flush=True)
    img[top_row:] = img[top_row:] * (1 - cover[..., None]) + ground
    sun_and_glare(img)
    pixels = encode(img)
    Image.fromarray(pixels).save(args.out, quality=88, optimize=True)
    luma = (pixels.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255
    solid = np.cos(np.radians(90 - (np.arange(H) + 0.5) * PX))[:, None]
    print("moon %s: %d KB, mean luminance %.1f%% (%.1f%% by solid angle); Earth at %.0f, %.0f, Sun at %.0f, %.0f (%.0fs)" % (
        os.path.basename(args.out), os.path.getsize(args.out) // 1024, luma.mean() * 100,
        (luma * solid).sum() / (solid.sum() * W) * 100, EARTH_LON, EARTH_EL, SUN_LON, SUN_EL, time.time() - t0))
    if args.preview:
        previews(args.out, args.preview)


if __name__ == "__main__":
    main()
