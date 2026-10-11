"""Lumiere's Orbit: the Earth from low orbit, 4096 x 2048 equirect, for a skybox on a Quest.

(draft)

    python3 orbit.py [OUT.jpg] [--preview DIR] [--jobs N]
"""
import argparse
import os
from concurrent.futures import ProcessPoolExecutor
from functools import lru_cache

import numpy as np
from PIL import Image

W, H = 4096, 2048
PX = 180.0 / H                     # degrees per pixel, down and across
PXR = np.pi / H                    # the same in radians
SEED = 4417
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "../quest/src/main/res/drawable-nodpi/lumiere_orbit.jpg")

R_E = 6371.0                       # the Earth's radius (km)
ALT = 400.0                        # the station's height
R_O = R_E + ALT
R_TOP = R_E + 100.0                # the top of the air
DIP = np.degrees(np.arccos(R_E / R_O))          # the limb's dip below the eye line, 19.8 degrees
TOP_DIP = np.degrees(np.arccos(R_TOP / R_O))    # where the air begins, 17.1 degrees down
SUN_LON, SUN_LAT = 72.0, 5.0
SCREEN_LON = 180.0
EXPOSURE = 12.0

LON = (np.arange(W) + 0.5) * PX
NA = 1024                                                 # the air is worked out at 1024 columns
LON_A = (np.arange(NA) + 0.5) * 360.0 / NA


def rng(k):
    """A generator per feature, so tuning one doesn't reshuffle the rest."""
    return np.random.default_rng([SEED, k])


def unit(lon, lat):
    lon, lat = np.radians(lon), np.radians(lat)
    return np.array([np.cos(lat) * np.cos(lon), np.sin(lat), np.cos(lat) * np.sin(lon)])


SUN = unit(SUN_LON, SUN_LAT)


def lin(c):
    c = np.asarray(c, np.float32) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# --- Noise on the sphere ---------------------------------------------------------------------

class Noise3:
    """3D gradient noise (Perlin's improved), unit spread, about -3.5..3.5."""

    def __init__(self, g):
        p = g.permutation(256).astype(np.int32)
        self.perm = np.concatenate([p, p])
        v = g.normal(size=(256, 3)).astype(np.float32)
        self.grad = v / np.linalg.norm(v, axis=1, keepdims=True)

    def __call__(self, x, y, z):
        xf, yf, zf = np.floor(x), np.floor(y), np.floor(z)
        fx, fy, fz = (x - xf).astype(np.float32), (y - yf).astype(np.float32), (z - zf).astype(np.float32)
        X, Y, Z = xf.astype(np.int64) & 255, yf.astype(np.int64) & 255, zf.astype(np.int64) & 255
        p, gr = self.perm, self.grad
        A, B = p[X] + Y, p[X + 1] + Y
        AA, AB, BA, BB = p[A] + Z, p[A + 1] + Z, p[B] + Z, p[B + 1] + Z

        def corner(h, ox, oy, oz):
            g = gr[p[h]]
            return g[:, 0] * (fx - ox) + g[:, 1] * (fy - oy) + g[:, 2] * (fz - oz)

        u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        w = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
        x00 = corner(AA, 0, 0, 0)
        x00 += u * (corner(BA, 1, 0, 0) - x00)
        x10 = corner(AB, 0, 1, 0)
        x10 += u * (corner(BB, 1, 1, 0) - x10)
        x01 = corner(AA + 1, 0, 0, 1)
        x01 += u * (corner(BA + 1, 1, 0, 1) - x01)
        x11 = corner(AB + 1, 0, 1, 1)
        x11 += u * (corner(BB + 1, 1, 1, 1) - x11)
        y0, y1 = x00 + v * (x10 - x00), x01 + v * (x11 - x01)
        return 5.2 * (y0 + w * (y1 - y0))


class Field:
    """A family of fractal noises for one feature, each octave turned and shifted so no lattice shows."""

    def __init__(self, key, count=4):
        g = rng(key)
        self.noises = [Noise3(g) for _ in range(count)]
        self.rot = []
        for _ in range(16):
            q, r = np.linalg.qr(g.normal(size=(3, 3)))
            self.rot.append(q * np.sign(np.diag(r)))
        self.off = g.uniform(-100, 100, (16, 3, 1))

    def octave(self, o, p, f):
        x = (self.rot[o] @ p) * f + self.off[o]
        return self.noises[o % len(self.noises)](x[0], x[1], x[2])

    def fbm(self, p, scale, foot, octaves, gain=0.5, lac=2.0, start=0):
        """Fractal noise at points p (3, N, km): the first octave `scale` km across; octaves finer than a
        pixel's footprint (km) fade to their mean. Returns the noise (unit-ish spread) and the variance lost."""
        n = p.shape[1]
        total = np.zeros(n, np.float32)
        lost = np.zeros(n, np.float32)
        f, a, norm = 1.0 / scale, 1.0, 0.0
        for o in range(octaves):
            att = np.clip(1.6 - 2.4 * f * foot, 0, 1).astype(np.float32)
            live = att > 0
            k = live.sum()
            if k == n:
                total += a * att * self.octave(o + start, p, f)
            elif k:
                total[live] += a * att[live] * self.octave(o + start, p[:, live], f)
            lost += a * a * (1 - att * att)
            norm += a * a
            f, a = f * lac, a * gain
        s = np.sqrt(norm)
        return total / s, lost / norm

    def ridged(self, p, scale, foot, octaves, gain=0.5, lac=2.0):
        """Ridged multifractal: sharp crests, detail mostly on them, about 0..1."""
        n = p.shape[1]
        total = np.zeros(n, np.float32)
        weight = np.ones(n, np.float32)
        f, a, norm = 1.0 / scale, 1.0, 0.0
        for o in range(octaves):
            att = np.clip(1.6 - 2.4 * f * foot, 0, 1).astype(np.float32)
            sig = (1 - np.minimum(np.abs(0.3 * self.octave(o + 8, p, f)), 1)) ** 2 * weight
            weight = np.clip(sig * 1.8, 0, 1)
            total += a * (att * sig + (1 - att) * 0.35)
            norm += a
            f, a = f * lac, a * gain
        return total / norm

    def vec(self, p, scale, foot, octaves):
        return np.stack([self.fbm(p, scale, foot, octaves, start=4 * i)[0] for i in range(3)])


F_LAND, F_WARP, F_ROCK, F_TONE, F_CLOUD, F_CWARP, F_CITY, F_SKY = (Field(k) for k in range(10, 18))


# --- The air ---------------------------------------------------------------------------------

BR = np.array([5.802, 13.558, 33.1], np.float32)[:, None, None] * 1e-3     # Rayleigh scattering, per km
HR = 8.0
BM_S, BM_E, HM, G = 3.996e-3, 4.44e-3, 1.2, 0.8                           # haze (Mie)
BO = np.array([0.650, 1.881, 0.085], np.float32)[:, None, None] * 1e-3     # ozone absorption
HT = np.sqrt(R_TOP ** 2 - R_E ** 2)


def density(z):
    return np.exp(-z / HR), np.exp(-z / HM), np.maximum(0, 1 - np.abs(z - 25) / 15)


@lru_cache(None)
def sun_lut(nr=96, nm=256, steps=600):
    """Sunlight's transmittance from any height toward the top of the air, as (3, nr, nm), parametrised
    as Bruneton's so the grazing rays near the horizon get most of the table."""
    xr = np.linspace(0, 1, nr)[:, None, None]
    xm = np.linspace(0, 1, nm)[None, :, None]
    rho = HT * xr
    r = np.sqrt(rho ** 2 + R_E ** 2)
    dmin, dmax = R_TOP - r, rho + HT
    d = dmin + xm * (dmax - dmin)
    mu = np.where(d > 0, (HT ** 2 - rho ** 2 - d ** 2) / (2 * r * np.maximum(d, 1e-6)), 1.0)
    s = (np.arange(steps) + 0.5)[None, None, :] / steps * d
    rr = np.sqrt(r * r + s * s + 2 * r * mu * s)
    dr, dm, do = density(rr - R_E)
    ds = d[..., 0] / steps
    tau = [(BR[c, 0, 0] * dr.sum(-1) + BM_E * dm.sum(-1) + BO[c, 0, 0] * do.sum(-1)) * ds for c in range(3)]
    return np.exp(-np.stack(tau)).astype(np.float32)


def sunlight(r, mu):
    """The sun's light reaching radius r (km) with the sun at cosine mu from the zenith: (3, ...) with the
    Earth's shadow, softened by the sun's own width."""
    lut = sun_lut()
    nr, nm = lut.shape[1:]
    rho = np.sqrt(np.maximum(r * r - R_E ** 2, 0))
    d = -r * mu + np.sqrt(np.maximum(r * r * (mu * mu - 1) + R_TOP ** 2, 0))
    dmin, dmax = R_TOP - r, rho + HT
    u = np.clip(rho / HT, 0, 1) * (nr - 1)
    v = np.clip((d - dmin) / (dmax - dmin), 0, 1) * (nm - 1)
    i0, j0 = np.minimum(u.astype(np.int64), nr - 2), np.minimum(v.astype(np.int64), nm - 2)
    fu, fv = (u - i0).astype(np.float32), (v - j0).astype(np.float32)
    t = (lut[:, i0, j0] * (1 - fu) + lut[:, i0 + 1, j0] * fu) * (1 - fv) \
        + (lut[:, i0, j0 + 1] * (1 - fu) + lut[:, i0 + 1, j0 + 1] * fu) * fv
    horizon = -np.sqrt(np.maximum(1 - (R_E / r) ** 2, 0))
    return t * smoothstep(horizon - 0.0047, horizon + 0.0047, mu)


def phases(c):
    pr = 3 / (16 * np.pi) * (1 + c * c)
    pm = 3 / (8 * np.pi) * (1 - G * G) * (1 + c * c) / ((2 + G * G) * (1 + G * G - 2 * G * c) ** 1.5)
    return pr, pm


def air(lat, steps=80):
    """The air along each ray from the station, for rows at lat (n,) and NA columns: the light it scatters
    toward you (3, n, NA), how much of what lies beyond it lets through (3, n, NA), and the ground's hits."""
    la, lo = np.radians(lat)[:, None], np.radians(LON_A)[None, :]
    dx, dy, dz = np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)
    b = R_O * dy
    top = b * b - (R_O ** 2 - R_TOP ** 2)
    enters = (top > 0) & (b < 0)
    t0 = -b - np.sqrt(np.maximum(top, 0))
    ground = b * b - (R_O ** 2 - R_E ** 2)
    hit = (ground >= 0) & (b < 0)
    t1 = np.where(hit, -b - np.sqrt(np.maximum(ground, 0)), -b + np.sqrt(np.maximum(top, 0)))
    ds = np.where(enters, (t1 - t0) / steps, 0).astype(np.float32)
    cos_sun = dx * SUN[0] + dy * SUN[1] + dz * SUN[2]
    pr, pm = phases(cos_sun)
    tau = np.zeros((3,) + dx.shape, np.float32)
    light = np.zeros((3,) + dx.shape, np.float32)
    glow = np.zeros(dx.shape, np.float32)
    for i in range(steps):
        t = t0 + (i + 0.5) * ds
        px, py, pz = t * dx, R_O + t * dy, t * dz
        r = np.sqrt(px * px + py * py + pz * pz)
        z = r - R_E
        dr, dm, do = density(z)
        ext = BR * dr + BM_E * dm + BO * do
        seen = np.exp(-(tau + 0.5 * ext * ds))
        mu = (px * SUN[0] + py * SUN[1] + pz * SUN[2]) / r
        light += seen * sunlight(r, mu) * (BR * dr * pr + BM_S * dm * pm) * ds
        # Airglow: a thin green shell 95 km up, seen only where the night hides the day's blue.
        glow += (seen[1] * np.exp(-((z - 95) / 4.5) ** 2) * smoothstep(0.1, -0.15, mu) * ds).astype(np.float32)
        tau += ext * ds
    light += glow * np.array([0.25, 1.0, 0.45], np.float32)[:, None, None] * 2.5e-5
    return light, np.exp(-tau), hit


def to_columns(a):
    """(..., NA) -> (..., W), wrapping round."""
    u = LON / 360 * NA - 0.5
    i0 = np.floor(u).astype(np.int64)
    f = (u - i0).astype(np.float32)
    return a[..., i0 % NA] * (1 - f) + a[..., (i0 + 1) % NA] * f


# --- The Earth -------------------------------------------------------------------------------

def arc_unit(az, arc):
    """A point on the Earth `arc` degrees of arc from the one below you, toward azimuth az."""
    az, arc = np.radians(az), np.radians(arc)
    return np.array([np.sin(arc) * np.cos(az), np.cos(arc), np.sin(arc) * np.sin(az)])


# Land masses (azimuth, arc from the point below you, radius, all degrees; and weight): rough shapes
# the noise breaks up into coasts.
LANDS = [
    (250, 11.0, 5.5, 1.0),     # the night side's continent, its coast toward you lit by cities
    (200, 15.5, 5.0, 0.8),     # running round under the screen to the limb
    (10, 12.0, 6.0, 0.9),      # a desert continent behind you, toward the sun's side
    (165, 2.8, 2.6, 0.9),      # a big island whose coast passes below you
    (312, 7.0, 1.4, 0.6),      # an island arc
    (326, 5.5, 1.0, 0.6),
    (338, 4.2, 0.9, 0.55),
    (60, 11.0, 7.0, -0.5),     # open ocean under the sun, for the glint and the storm
]
# Storms (azimuth, arc, radius, turn in radians, eye radius in degrees).
STORMS = [
    (52, 5.8, 3.4, 9.0, 0.16),     # a hurricane over the open ocean, toward the sun
    (118, 11.0, 5.5, 5.0, 0.0),    # a mid-latitude low, its comma trailing a front
    (300, 13.0, 4.0, 4.0, 0.0),
]


def ang(q, k):
    return np.degrees(np.arccos(np.clip(k[0] * q[0] + k[1] * q[1] + k[2] * q[2], -1, 1)))


def land(q, foot):
    """The land's height above sea level (about -1..1, 0 the coast) and the variance lost to the footprint."""
    p = q * R_E
    warp = F_WARP.vec(p, 2600, foot, 3) * 520
    pw = p + warp
    macro = sum(w * np.exp(-(ang(q, arc_unit(az, arc)) / rad) ** 2) for az, arc, rad, w in LANDS)
    broad, _ = F_LAND.fbm(pw, 3200, foot, 3)
    detail, lost = F_LAND.fbm(pw + 0.4 * warp, 900, foot, 13, gain=0.52, start=3)
    e = macro + 0.32 * broad + 0.34 * detail - 0.52
    return e, lost * 0.34 ** 2


def clouds(q, foot):
    """Cloud cover (0..1) at points q, with swirls round the storms."""
    p = q * R_E
    core = np.zeros(q.shape[1], np.float32)
    for az, arc, rad, turn, eye in STORMS:
        k = arc_unit(az, arc)
        a = ang(q, k)
        spin = turn * np.exp(-(a / rad) ** 1.3)
        c, s = np.cos(spin), np.sin(spin)
        kp = k[0] * p[0] + k[1] * p[1] + k[2] * p[2]
        cross = np.stack([k[1] * p[2] - k[2] * p[1], k[2] * p[0] - k[0] * p[2], k[0] * p[1] - k[1] * p[0]])
        p = p * c + cross * s + k[:, None] * kp * (1 - c)
        dense = np.exp(-(a / (rad * 0.32)) ** 2)
        if eye > 0:
            dense = dense * smoothstep(eye, eye * 2.2, a)
        core = np.maximum(core, dense)
    warp = F_CWARP.vec(p, 1400, foot, 3) * 300
    systems, _ = F_CLOUD.fbm(p + warp, 900, foot, 3)
    body, lost = F_CLOUD.fbm(p + 0.6 * warp, 220, foot, 11, gain=0.56, start=3)
    v = 0.55 * systems + 0.75 * body + 1.3 * core - 0.35
    w = np.sqrt(0.18 ** 2 + lost * 0.75 ** 2)
    return smoothstep(-w, w, v) * smoothstep(-0.6, 0.8, v + 0.2)


def surface(q, d, t):
    """The light leaving the ground and clouds at points q (3, N) seen along d (3, N) from t km away."""
    n = q.shape[1]
    mu_v = np.clip(-(d * q).sum(0), 1e-3, 1)
    foot = (t * PXR / mu_v ** 0.75).astype(np.float32)
    mu_s = (q * SUN[:, None]).sum(0)
    e, lost = land(q, foot)
    wc = np.sqrt(0.012 ** 2 + lost)
    is_land = smoothstep(-wc, wc, e)

    # Ground colour.
    p = q * R_E
    tone, _ = F_TONE.fbm(p, 1600, foot, 4)
    grain, _ = F_TONE.fbm(p, 60, foot, 7, gain=0.6, start=5)
    rock = F_ROCK.ridged(p, 420, foot, 8)
    hills = rock * smoothstep(0.02, 0.35, e)
    dry = smoothstep(-0.3, 0.6, tone + 1.2 * np.exp(-(ang(q, arc_unit(14, 12)) / 6) ** 2) - 0.3)
    forest, savanna = lin((22, 36, 18)), lin((70, 72, 40))
    desert, sand = lin((150, 98, 58)), lin((178, 148, 104))
    rocky, snow = lin((86, 76, 66)), lin((214, 220, 228))
    green = forest[:, None] + smoothstep(-0.5, 0.8, grain)[None] * (savanna - forest)[:, None]
    arid = desert[:, None] + smoothstep(-0.6, 0.6, grain)[None] * (sand - desert)[:, None]
    ground = green + dry[None] * (arid - green)
    ground = ground + smoothstep(0.35, 0.75, hills)[None] * (rocky[:, None] - ground)
    ground = ground + smoothstep(0.72, 0.85, hills * (1 - 0.5 * dry))[None] * (snow[:, None] - ground)
    ground *= (1 + 0.18 * np.clip(grain, -2, 2))[None]
    deep, shelf = lin((4, 13, 32)), lin((14, 52, 64))
    sea = deep[:, None] + smoothstep(-0.12, -0.005, e)[None] * (shelf - deep)[:, None]
    albedo = sea + is_land[None] * (ground - sea)

    # Light on the ground: the sun through the air, a little skylight, and a little moonlight at night.
    sun = sunlight(np.full(n, R_E), mu_s)
    relief = mu_s
    sky = lin((120, 160, 230))[:, None] * (0.02 + 0.06 * smoothstep(-0.15, 0.3, mu_s))[None]
    lit = sun * np.maximum(relief, 0)[None] + sky + 0.0006
    out = albedo / np.pi * lit

    # Glint: the sun's reflection on open water.
    v = -d
    h = v + SUN[:, None]
    h /= np.linalg.norm(h, axis=0)
    nh = np.clip((h * q).sum(0), 1e-3, 1)
    vh = np.clip((v * h).sum(0), 0, 1)
    s2 = 0.03
    tan2 = (1 - nh * nh) / (nh * nh)
    beck = np.exp(-tan2 / s2) / (np.pi * s2 * nh ** 4)
    fres = 0.02 + 0.98 * (1 - vh) ** 5
    out += sun * (fres * beck / (4 * mu_v) * (1 - is_land))[None]

    # Clouds.
    cover = clouds(q, foot)
    cover = 1 - (1 - cover) ** (1 / np.maximum(mu_v, 0.05) ** 0.4)
    ctop = sunlight(np.full(n, R_E + 4.0), mu_s)
    cl = 0.82 / np.pi * (ctop * np.maximum(mu_s + 0.06, 0)[None] ** 0.8 + sky * 1.4 + 0.0006)
    out = out + cover[None] * (cl - out)
    return out


def shade(lat):
    """Rows at lat (n,): the light reaching you from the air and the ground, and how much light from beyond
    (the stars) the air lets through, both (n, W, 3)."""
    light, through, _ = air(lat)
    light, through = to_columns(light), to_columns(through)
    la, lo = np.radians(lat)[:, None], np.radians(LON)[None, :]
    d = np.stack([np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)])
    b = R_O * d[1]
    disc = b * b - (R_O ** 2 - R_E ** 2)
    hit = (disc >= 0) & (b < 0)
    out = light.copy()
    if hit.any():
        t = -b[hit] - np.sqrt(disc[hit])
        dd = d[:, hit]
        q = (dd * t + np.array([0, R_O, 0])[:, None]) / R_E
        out[:, hit] += through[:, hit] * surface(q, dd, t)
    beyond = through * (~hit)[None]
    return out.transpose(1, 2, 0), beyond.transpose(1, 2, 0)


def shade_job(job):
    rows, k = job
    lat = (90 - (np.repeat(rows, k) + (np.tile(np.arange(k), len(rows)) + 0.5) / k) * PX)
    out, beyond = shade(lat)
    return rows, out.reshape(len(rows), k, W, 3).mean(1), beyond.reshape(len(rows), k, W, 3).mean(1)


# --- Space -----------------------------------------------------------------------------------

def space():
    """Stars and the Milky Way, black between."""
    out = np.zeros((H, W, 3), np.float32)
    # The Milky Way, worked out at half size and enlarged.
    h2, w2 = H // 2, W // 2
    la = np.radians(90 - (np.arange(h2) + 0.5) * 180 / h2)[:, None]
    lo = np.radians((np.arange(w2) + 0.5) * 360 / w2)[None, :]
    p = np.stack([np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)]).reshape(3, -1)
    centre = unit(236, 34)
    pole = np.cross(centre, unit(340, 40))
    pole /= np.linalg.norm(pole)
    off = np.abs(pole @ p)
    near = centre @ p
    clouds_, _ = F_SKY.fbm(p * 1000, 260, np.full(p.shape[1], 1.0), 6, gain=0.55)
    dust, _ = F_SKY.fbm(p * 1000, 120, np.full(p.shape[1], 1.0), 6, gain=0.6, start=6)
    band = np.exp(-(off / 0.17) ** 2) * (0.55 + 0.45 * np.tanh(clouds_))
    lanes = smoothstep(0.1, 0.9, dust) * np.exp(-(off / 0.08) ** 2)
    bulge = np.exp(-((1 - near) / 0.06)) * np.exp(-(off / 0.12) ** 2)
    mw = (band * (1 - 0.75 * lanes))[:, None] * lin((26, 26, 32)) + (bulge * (1 - 0.8 * lanes))[:, None] * lin((40, 34, 26))
    mw = mw.reshape(h2, w2, 3) * 0.35
    up = np.repeat(np.repeat(mw, 2, 0), 2, 1)
    out += up

    # Stars, even over the sphere, on a power law of brightness, round on the sphere.
    g = rng(30)
    count = 14000
    v = g.normal(size=(count, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    lat = np.degrees(np.arcsin(v[:, 1]))
    lon = np.degrees(np.arctan2(v[:, 2], v[:, 0])) % 360
    mag = g.pareto(2.3, count) + 1
    b = np.minimum(0.006 * mag ** 1.4, 0.3)
    temp = g.random(count)
    tint = np.stack([np.interp(temp, [0, 0.15, 0.6, 1], [0.70, 0.85, 1.00, 1.00]),
                     np.interp(temp, [0, 0.15, 0.6, 1], [0.80, 0.90, 0.97, 0.82]),
                     np.interp(temp, [0, 0.15, 0.6, 1], [1.00, 1.00, 0.92, 0.62])], 1)
    for la_, lo_, b_, t_ in zip(lat, lon, b, tint):
        row, col = (90 - la_) / PX - 0.5, lo_ / PX - 0.5
        cosl = max(np.cos(np.radians(la_)), 0.02)
        r0, r1 = max(int(row) - 2, 0), min(int(row) + 4, H)
        span = min(int(2.5 / cosl) + 2, W // 2)
        cols = np.arange(int(col) - span, int(col) + span + 1)
        dy = (np.arange(r0, r1)[:, None] - row) * PX
        dx = (((cols[None, :] - col) * PX + 180) % 360 - 180) * cosl
        sig = 0.05 + 0.02 * min(b_ / 0.1, 1)
        spot = b_ * np.exp(-(dy * dy + dx * dx) / (2 * sig ** 2))
        out[r0:r1, cols % W] += spot[..., None] * t_
    return out


def sun_glare(img):
    """The sun's disc and its glare, over everything."""
    la, lo = np.radians(90 - (np.arange(H) + 0.5) * PX)[:, None], np.radians(LON)[None, :]
    c = np.cos(la) * np.cos(lo) * SUN[0] + np.sin(la) * SUN[1] + np.cos(la) * np.sin(lo) * SUN[2]
    g = np.degrees(np.arccos(np.clip(c, -1, 1))).astype(np.float32)
    disc = smoothstep(0.42, 0.34, g) * (1 - 0.35 * (g / 0.4) ** 2)
    glare = 0.08 * np.exp(-g / 0.9) + 0.012 * np.exp(-g / 4.0) + 0.002 * np.exp(-g / 16.0)
    img += (disc * 8 + glare)[..., None] * np.array([1.0, 0.97, 0.92], np.float32)
    return img


# --- Output ----------------------------------------------------------------------------------

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


def tonemap(x):
    """Linear below the knee, then a soft shoulder that never reaches past white."""
    k = 0.62
    return np.where(x < k, x, k + (1 - k) * (1 - np.exp(-(x - k) / (1 - k))))


def encode(img):
    """sRGB with a fine grain that survives the JPEG, so the dark gradients don't band."""
    g = rng(9)
    grain = g.normal(0, 1, (H, W, 1)).astype(np.float32)
    grain = blur(grain, 0.55, 0.55)[..., 0]
    grain *= 0.9 / grain.std()
    s = srgb(tonemap(img)) * 255 + grain[..., None]
    return np.clip(np.round(s), 0, 255).astype(np.uint8)


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
    lat = np.degrees(np.arcsin(np.clip(d[..., 1], -1, 1)))
    lon = np.degrees(np.arctan2(d[..., 2], d[..., 0])) % 360
    return bilinear(img.astype(np.float32), (90 - lat) / PX - 0.5, lon / PX - 0.5)


def previews(path, folder):
    os.makedirs(folder, exist_ok=True)
    img = np.asarray(Image.open(path).convert("RGB"))
    Image.fromarray(img).resize((2048, 1024), Image.LANCZOS).save(os.path.join(folder, "panorama.png"))
    views = {"forward": (SCREEN_LON, 0, 90), "sun": (SUN_LON, SUN_LAT, 90), "down": (SCREEN_LON, -90, 90),
             "down45_sun": (SUN_LON + 18, -45, 90), "down45_night": (SUN_LON + 180, -45, 90),
             "up": (SCREEN_LON, 90, 90), "seam": (0, -10, 90), "limb": (SCREEN_LON, -19, 30),
             "night": (SUN_LON + 180, -26, 60)}
    for name, (yaw, pitch, fov) in views.items():
        view = perspective(img, yaw, pitch, fov)
        Image.fromarray(np.clip(view + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(folder, name + ".png"))


def render(jobs):
    img = space()
    first = int(np.ceil((90 + TOP_DIP - 0.2) / PX - 0.5))          # the first row the air reaches
    limb = (90 + DIP) / PX
    fine = [r for r in range(first, H) if abs(r + 0.5 - limb) < 0.6 / PX or r < limb]   # the air's band
    coarse = [r for r in range(first, H) if r not in set(fine)]
    tasks = [(np.array(fine[i:i + 4]), 4) for i in range(0, len(fine), 4)]
    tasks += [(np.array(coarse[i:i + 24]), 1) for i in range(0, len(coarse), 24)]
    with ProcessPoolExecutor(jobs) as pool:
        for rows, out, beyond in pool.map(shade_job, tasks):
            img[rows] = out + beyond * img[rows]
    return sun_glare(img * EXPOSURE)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?", default=OUT)
    ap.add_argument("--preview", metavar="DIR", help="also write a panorama and perspective views here")
    ap.add_argument("--jobs", type=int, default=os.cpu_count(), help="processes to draw with")
    args = ap.parse_args()
    pixels = encode(render(args.jobs))
    Image.fromarray(pixels).save(args.out, quality=88, optimize=True)
    luma = (pixels.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255
    solid = np.cos(np.radians(90 - (np.arange(H) + 0.5) * PX))[:, None]
    print("orbit %s: %d KB, mean luminance %.1f%% (%.1f%% by solid angle)" % (
        os.path.basename(args.out), os.path.getsize(args.out) // 1024, luma.mean() * 100,
        (luma * solid).sum() / (solid.sum() * W) * 100))
    if args.preview:
        previews(args.out, args.preview)


if __name__ == "__main__":
    main()
