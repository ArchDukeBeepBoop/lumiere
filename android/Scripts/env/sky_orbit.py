"""Lumiere's Orbit: the Earth from low orbit, 4096 x 2048 equirect, for a skybox on a Quest.

The station 400 km up at dawn: the limb about 20 degrees below the eye line all round, the sun just
risen over it to your left with its glint on the open sea and a hurricane turning beside it; under you a
big island, a desert continent behind; to your right the night side, its coasts lit by cities under a
thin green airglow. The air is a single-scattering Rayleigh/Mie/ozone march, the ground and clouds
fractal noise on the sphere, faded below each pixel's footprint so the limb doesn't shimmer; a faint
Milky Way and stars above.

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
EXPOSURE = 11.0

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


def col(*c):
    return np.array(c, np.float32)[:, None]


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
        for _ in range(24):
            q, r = np.linalg.qr(g.normal(size=(3, 3)))
            self.rot.append(q * np.sign(np.diag(r)))
        self.off = g.uniform(-100, 100, (24, 3))

    def octave(self, o, p, f):
        m, off = self.rot[o] * f, self.off[o]
        x = m[0, 0] * p[0] + m[0, 1] * p[1] + m[0, 2] * p[2] + off[0]
        y = m[1, 0] * p[0] + m[1, 1] * p[1] + m[1, 2] * p[2] + off[1]
        z = m[2, 0] * p[0] + m[2, 1] * p[1] + m[2, 2] * p[2] + off[2]
        return self.noises[o % len(self.noises)](x, y, z)

    def _sum(self, p, scale, foot, octaves, gain, lac, start, shape, fade_to):
        n = p.shape[1]
        total = np.zeros(n, np.float32)
        lost = np.zeros(n, np.float32)
        f, a, norm = 1.0 / scale, 1.0, 0.0
        for o in range(octaves):
            att = np.clip(1.6 - 2.4 * f * foot, 0, 1).astype(np.float32)
            live = att > 0
            k = live.sum()
            if k == n:
                total += a * (att * shape(self.octave(o + start, p, f)) + (1 - att) * fade_to)
            else:
                total += a * fade_to
                if k:
                    total[live] += a * att[live] * (shape(self.octave(o + start, p[:, live], f)) - fade_to)
            lost += a * a * (1 - att * att)
            norm += a * a
            f, a = f * lac, a * gain
        return total, lost, norm

    def fbm(self, p, scale, foot, octaves, gain=0.5, lac=2.0, start=0):
        """Fractal noise at points p (3, N, km): the first octave `scale` km across; octaves finer than a
        pixel's footprint (km) fade to their mean. Returns the noise (unit spread) and the variance lost."""
        total, lost, norm = self._sum(p, scale, foot, octaves, gain, lac, start, lambda v: v, 0.0)
        return total / np.sqrt(norm), lost / norm

    def billow(self, p, scale, foot, octaves, gain=0.5, lac=2.0, start=0):
        """Puffy noise (|noise|, rounded): heaps divided by creases, about -1..1, and the variance lost."""
        total, lost, norm = self._sum(p, scale, foot, octaves, gain, lac, start,
                                      lambda v: 1 - 2 * np.exp(-0.9 * v * v), 2 * 0.62 - 1)
        return total / np.sqrt(norm), lost / norm * 0.35

    def ridged(self, p, scale, foot, octaves, gain=0.5, lac=2.0, start=8):
        """Ridged multifractal: sharp crests, detail mostly on them, about 0..1."""
        n = p.shape[1]
        total = np.zeros(n, np.float32)
        weight = np.ones(n, np.float32)
        f, a, norm = 1.0 / scale, 1.0, 0.0
        for o in range(octaves):
            att = np.clip(1.6 - 2.4 * f * foot, 0, 1).astype(np.float32)
            sig = (1 - np.minimum(np.abs(0.3 * self.octave(o + start, p, f)), 1)) ** 2 * weight
            weight = np.clip(sig * 1.8, 0, 1)
            total += a * (att * sig + (1 - att) * 0.3)
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


def sunlight(r, mu, adapt=1.0):
    """The sun's light reaching radius r (km) with the sun at cosine mu from the zenith: (3, ...) with the
    Earth's shadow, softened by the sun's own width. adapt < 1 is the eye making allowance for its colour."""
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
    if adapt != 1:
        t = t ** adapt
    horizon = -np.sqrt(np.maximum(1 - (R_E / r) ** 2, 0))
    return t * smoothstep(horizon - 0.0047, horizon + 0.0047, mu)


def phases(c):
    pr = 3 / (16 * np.pi) * (1 + c * c)
    pm = 3 / (8 * np.pi) * (1 - G * G) * (1 + c * c) / ((2 + G * G) * (1 + G * G - 2 * G * c) ** 1.5)
    return pr, 0.75 * pm + 0.25 / (4 * np.pi)       # the haze: mostly forward, some every way


def air(lat, steps=80):
    """The air along each ray from the station, for rows at lat (n,) and NA columns: the light it scatters
    toward you (3, n, NA) and how much of what lies beyond it lets through (3, n, NA)."""
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
    dusk = np.zeros((3,) + dx.shape, np.float32)
    violet = np.array([0.9, 0.0, 0.1], np.float32)[:, None, None]
    for i in range(steps):
        t = t0 + (i + 0.5) * ds
        px, py, pz = t * dx, R_O + t * dy, t * dz
        r = np.sqrt(px * px + py * py + pz * pz)
        z = r - R_E
        dr, dm, do = density(z)
        ext = BR * dr + BM_E * dm + BO * do
        seen = np.exp(-(tau + 0.5 * ext * ds))
        mu = (px * SUN[0] + py * SUN[1] + pz * SUN[2]) / r
        # High up, where the air is thinnest, the blue fades through violet into black.
        scatter = BR * dr * (1 + violet * smoothstep(22, 50, z)) * pr + BM_S * dm * pm
        light += seen * sunlight(r, mu, 0.9) * scatter * ds
        # Where the sunlight only grazes this air, it has come through so much more that it is orange:
        # the band of sunset along the terminator, low down, where it meets the limb.
        graze = mu + np.sqrt(np.maximum(1 - (R_E / r) ** 2, 0))
        dusk += seen * (np.exp(-z / 7.0) * np.exp(-((graze - 0.03) / 0.03) ** 2) * ds)
        # Airglow: a thin green shell 95 km up, seen only where the night hides the day's blue.
        glow += (seen[1] * np.exp(-((z - 95) / 3.5) ** 2) * smoothstep(0.1, -0.15, mu) * ds).astype(np.float32)
        tau += ext * ds
    light += glow * np.array([0.3, 1.0, 0.5], np.float32)[:, None, None] * 2.2e-6
    light += dusk * np.array([1.0, 0.42, 0.12], np.float32)[:, None, None] * 5e-4
    return light, np.exp(-tau)


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


def ang(q, k):
    return np.degrees(np.arccos(np.clip(k[0] * q[0] + k[1] * q[1] + k[2] * q[2], -1, 1)))


def toward(q, k, dist):
    """Points q moved dist (km, per point) along the surface toward direction k."""
    kt = k[:, None] - (k[:, None] * q).sum(0) * q
    kt /= np.maximum(np.linalg.norm(kt, axis=0), 1e-9)
    a = dist / R_E
    return q * np.cos(a) + kt * np.sin(a)


# Land masses (azimuth, arc from the point below you, radius, all degrees; and weight): rough shapes
# the noise breaks up into coasts.
LANDS = [
    (246, 14.0, 6.5, 1.15),    # the night side's continent, its coast toward you lit by cities
    (285, 9.0, 3.0, 0.8),      # a peninsula reaching from it into the dusk
    (196, 15.5, 4.5, 0.8),     # running round under the screen to the limb
    (15, 12.0, 6.5, 1.0),      # a desert continent behind you, toward the sun's side
    (160, 2.6, 2.4, 0.9),      # a big island whose coast passes below you
    (322, 6.5, 1.0, 0.55),     # an island arc
    (334, 5.0, 0.8, 0.55),
    (345, 3.8, 0.7, 0.5),
    (75, 9.0, 7.0, -0.7),      # open ocean under the sun, for the glint and the storm
    (235, 6.5, 2.6, -0.6),     # a gulf between the island and the night's coast
]
DESERT = (10, 12.0, 6.0)
# Storms (azimuth, arc, radius in degrees, turn in radians, eye radius in degrees).
STORMS = [
    (55, 6.0, 3.2, 3.5, 0.16),     # a hurricane over the open ocean, toward the sun
    (118, 11.0, 3.5, 1.5, 0.0),    # a mid-latitude low, a front trailing from it
]
FRONTS = [(118, 11.0, 172, 6.0, 1.0)]  # from (azimuth, arc) to (azimuth, arc), width in degrees


def land(q, foot):
    """The land's height above sea level (about -1..1, 0 the coast) and the variance lost to the footprint."""
    p = q * R_E
    warp = F_WARP.vec(p, 2600, foot, 3) * 520
    pw = p + warp
    macro = sum(w * np.exp(-(ang(q, arc_unit(az, arc)) / rad) ** 2) for az, arc, rad, w in LANDS)
    broad, _ = F_LAND.fbm(pw, 3200, foot, 3)
    detail, lost = F_LAND.fbm(pw + 0.4 * warp, 900, foot, 13, gain=0.52, start=3)
    e = macro + 0.2 * broad + 0.3 * detail - 0.5
    return e, lost * 0.34 ** 2


def basis(k):
    e1 = np.cross(k, [0.0, 1.0, 0.0])
    e1 /= np.linalg.norm(e1)
    return e1, np.cross(k, e1)


def clouds(q, foot):
    """Cloud cover (0..1) and thickness (0..1) at points q: weather systems, fields of heaped cumulus, a
    long front and the storms' spirals."""
    p0 = p = q * R_E
    storm = np.zeros(q.shape[1], np.float32)
    for az, arc, rad, turn, eye in STORMS:
        k = arc_unit(az, arc)
        a = ang(q, k)
        spin = turn * np.exp(-(a / rad) ** 2)
        c, s = np.cos(spin), np.sin(spin)
        kp = k[0] * p[0] + k[1] * p[1] + k[2] * p[2]
        cross = np.stack([k[1] * p[2] - k[2] * p[1], k[2] * p[0] - k[0] * p[2], k[0] * p[1] - k[1] * p[0]])
        p = p * c + cross * s + k[:, None] * kp * (1 - c)
        e1, e2 = basis(k)
        th = np.arctan2(e2 @ q, e1 @ q)
        arms = 0.5 + 0.5 * np.cos(2 * th - 4.5 * np.log(np.maximum(a, 0.05) / rad))
        # A dense round canopy over the middle, two bands winding out of it.
        body = np.maximum(np.exp(-(a / (0.42 * rad)) ** 4), arms ** 2 * np.exp(-(a / (1.3 * rad)) ** 2))
        if eye > 0:
            body *= smoothstep(eye, eye * 2.0, a)
        storm = np.maximum(storm, body)
    for az0, arc0, az1, arc1, width in FRONTS:
        a0, a1 = arc_unit(az0, arc0), arc_unit(az1, arc1)
        m = np.cross(a0, a1)
        m /= np.linalg.norm(m)
        off = np.degrees(np.arcsin(np.clip(m @ q, -1, 1)))
        along = (q * (a0 + a1)[:, None]).sum(0) / np.linalg.norm(a0 + a1)
        span = np.degrees(np.arccos(np.clip(a0 @ a1, -1, 1))) / 2
        bend = 0.8 * np.sin(np.degrees(np.arccos(np.clip(along, -1, 1))) / span * 1.6)
        storm = np.maximum(storm, np.exp(-((off - bend) / width) ** 2) * smoothstep(np.cos(np.radians(span + 1.5)),
                                                                                      np.cos(np.radians(span - 1.5)), along))
    warp = F_CWARP.vec(p, 2000, foot, 2) * 240
    systems, _ = F_CLOUD.fbm(p + warp, 1300, foot, 3)
    # The spiral turns the weather systems; the finer cloud only half as far, and the heaps not at all, so
    # the shear doesn't comb them into streaks finer than a pixel.
    body, lost_b = F_CLOUD.fbm(0.5 * (p + p0) + 0.5 * warp, 300, foot, 5, gain=0.55, start=3)
    heaps, lost_h = F_CLOUD.billow(p0 + 0.2 * warp, 46, foot, 6, gain=0.55, start=8)
    # Inside a storm the canopy is whole: the fair-weather breaks are mostly smoothed over.
    calm = 1 - 0.7 * storm
    v = (0.5 * systems + 0.38 * body + 0.32 * heaps) * calm + 1.5 * storm - 0.32
    w = np.sqrt(0.06 ** 2 + lost_b * 0.38 ** 2 + lost_h * 0.32 ** 2)
    cover = smoothstep(-w, w, v)
    thick = smoothstep(-0.05, 0.7, v) * (0.75 + 0.25 * np.clip(heaps, -1, 1))
    return cover, thick


def lights(q, e, foot):
    """City lights: towns crowding the coasts and rivers, big cities among them, fewer inland."""
    p = q * R_E
    region, _ = F_CITY.fbm(p, 800, foot, 3)
    metro, lm = F_CITY.fbm(p, 110, foot, 5, start=3)
    town, lt = F_CITY.fbm(p, 16, foot, 6, gain=0.6, start=8)
    coast = np.exp(-np.maximum(e, 0) / 0.05)
    pop = smoothstep(-0.8, 0.6, region) * (0.2 + 0.8 * coast)
    wm, wt = np.sqrt(0.15 ** 2 + lm), np.sqrt(0.15 ** 2 + lt)
    cities = smoothstep(0.8 - wm, 0.8 + wm, metro + 0.5 * coast)
    towns = smoothstep(0.9 - wt, 0.9 + wt, town + 0.6 * coast)
    glow = pop * (cities * (0.45 + 0.55 * smoothstep(-0.6, 1.2, town)) + 0.3 * towns)
    return glow


def surface(q, d, t):
    """The light leaving the ground and clouds at points q (3, N) seen along d (3, N) from t km away."""
    n = q.shape[1]
    mu_v = np.clip(-(d * q).sum(0), 1e-3, 1)
    foot = (t * PXR / mu_v ** 0.75).astype(np.float32)
    mu_s = SUN @ q
    e, lost = land(q, foot)
    wc = np.sqrt(0.012 ** 2 + lost)
    is_land = smoothstep(-wc, wc, e)
    p = q * R_E

    # Ground colour.
    tone, _ = F_TONE.fbm(p, 1600, foot, 4)
    grain, _ = F_TONE.fbm(p, 70, foot, 8, gain=0.6, start=5)
    dry = smoothstep(-0.3, 0.6, tone + 1.3 * np.exp(-(ang(q, arc_unit(*DESERT[:2])) / DESERT[2]) ** 2) - 0.35)
    green = col(0.06, 0.09, 0.035) + smoothstep(-0.6, 0.9, grain) * col(0.14, 0.09, 0.05)
    arid = col(0.42, 0.27, 0.14) + smoothstep(-0.7, 0.7, grain) * col(0.14, 0.14, 0.12)
    ground = green + dry * (arid - green)

    # Mountains, lit on the faces toward the low sun and dark behind: the slope toward the sun from
    # the ridges' height a little way off.
    relief = mu_s.copy()
    on = is_land > 0.01
    if on.any():
        ql, fl = q[:, on], foot[on]
        inland = smoothstep(0.02, 0.3, e[on])
        rock = F_ROCK.ridged(ql * R_E, 380, fl, 9)
        step = np.maximum(2.5 * fl, 3.0)
        ahead = F_ROCK.ridged(toward(ql, SUN, step) * R_E, 380, fl, 9)
        km = 4.0 * inland
        slope = (ahead - rock) * km / step
        relief[on] = mu_s[on] - 3.0 * slope * np.sqrt(np.maximum(1 - mu_s[on] ** 2, 0))
        hills = rock * inland
        g = ground[:, on]
        g = g + smoothstep(0.38, 0.7, hills) * (col(0.15, 0.13, 0.11) - g)
        g = g + smoothstep(0.7, 0.8, hills * (1 - 0.6 * dry[on])) * (col(0.75, 0.78, 0.82) - g)
        ground[:, on] = g
    ground *= 1 + 0.15 * np.clip(grain, -2, 2)
    sea = col(0.004, 0.013, 0.032) + smoothstep(-0.12, -0.005, e) * col(0.02, 0.06, 0.05)
    albedo = sea + is_land * (ground - sea)

    # Light on the ground: the low sun through the air (as the eye allows for its colour), a little
    # skylight, and long shadows from the clouds.
    sun = sunlight(np.full(n, R_E), mu_s, 0.4)
    sky = col(0.35, 0.55, 1.0) * (0.05 * smoothstep(-0.1, 0.35, mu_s))
    cover, thick = clouds(q, foot)
    shade_at = toward(q, SUN, np.clip(4.0 * np.sqrt(np.maximum(1 - mu_s ** 2, 0)) / np.maximum(mu_s, 0.04), 0, 90))
    shadow, _ = clouds(shade_at, np.maximum(foot, 3.0))
    lit = sun * (np.maximum(relief, 0) ** 0.75 * (1 - 0.8 * shadow)) + sky + 0.0002
    out = albedo / np.pi * lit

    # Glint: the sun's reflection on open water (Beckmann waves, Smith masking).
    v = -d
    h = v + SUN[:, None]
    h /= np.linalg.norm(h, axis=0)
    nh = np.clip((h * q).sum(0), 1e-3, 1)
    vh = np.clip((v * h).sum(0), 0, 1)
    s2 = 0.01
    beck = np.exp(-(1 - nh * nh) / (nh * nh * s2)) / (np.pi * s2 * nh ** 4)
    fres = 0.02 + 0.98 * (1 - vh) ** 5

    def smith(mu):
        a = mu / (np.sqrt(s2) * np.sqrt(np.maximum(1 - mu * mu, 1e-6)))
        return np.where(a < 1.6, (3.535 * a + 2.181 * a * a) / (1 + 2.276 * a + 2.577 * a * a), 1)

    glint = fres * beck * smith(mu_v) * smith(np.clip(mu_s, 1e-3, 1)) / (4 * mu_v) * 0.045
    out += sun * (glint * (1 - is_land) * (1 - cover))

    # Clouds: white tops in sunlight (warm only near the terminator), still catching it a while after the
    # ground below has gone dark, thicker toward the limb as you see their sides.
    cover = 1 - (1 - cover) ** (1 / np.maximum(mu_v, 0.05) ** 0.45)
    tops = sunlight(np.full(n, R_E + 6.0), mu_s, 0.4)
    bright = 0.5 + 0.45 * thick
    cl = bright / np.pi * (tops * np.maximum(mu_s + 0.05, 0) ** 0.55 * 0.9 + sky * 1.5 + 0.0002)

    # City lights, on the night side, through thin cloud and glowing under thick.
    dark = smoothstep(0.03, -0.05, mu_s) * is_land
    night = dark > 0.01
    if night.any():
        glow = np.zeros(n, np.float32)
        glow[night] = lights(q[:, night], e[night], foot[night]) * dark[night]
        city = glow * (col(1.0, 0.62, 0.26) + smoothstep(0.4, 1.0, glow) * col(0.0, 0.18, 0.2)) * 0.11
        out += city
        cl = cl + city * 0.35
    return out + cover * (cl - out)


def shade(lat):
    """Rows at lat (n,): the light reaching you from the air and the ground, and how much light from beyond
    (the stars) the air lets through, both (n, W, 3)."""
    light, through = air(lat)
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

GALAXY = unit(292, 30)                      # the Milky Way's heart, up and off to the night side
GALAXY_POLE = np.cross(GALAXY, unit(118, 34))
GALAXY_POLE /= np.linalg.norm(GALAXY_POLE)


def milky_way():
    """The Milky Way: a faint band of star clouds along a great circle, split by dark lanes of dust that
    run along it, brighter and warmer toward its heart. Worked out at half size and enlarged."""
    h2, w2 = H // 2, W // 2
    la = np.radians(90 - (np.arange(h2) + 0.5) * 180 / h2)[:, None]
    lo = np.radians((np.arange(w2) + 0.5) * 360 / w2)[None, :]
    p = np.stack([np.cos(la) * np.cos(lo), np.sin(la) * np.ones_like(lo), np.cos(la) * np.sin(lo)]).reshape(3, -1)
    off = GALAXY_POLE @ p
    near = GALAXY @ p
    # Squeezed across the band, so the clouds and lanes stretch along it.
    sq = (p + 2.0 * off * GALAXY_POLE[:, None]) * 1000
    foot = np.full(p.shape[1], 3.0, np.float32)
    starclouds, _ = F_SKY.fbm(sq, 150, foot, 7, gain=0.62)
    lane, _ = F_SKY.fbm(sq + 37, 110, foot, 7, gain=0.62, start=7)
    a = np.abs(off)
    band = np.exp(-(a / 0.09) ** 2) * (0.35 + 0.65 * smoothstep(-1.2, 1.4, starclouds))
    dust = smoothstep(0.2, 1.1, lane) * np.exp(-((off - 0.012) / 0.05) ** 2)
    heart = np.exp(-(1 - near) / 0.04) * np.exp(-(a / 0.08) ** 2)
    mw = (band * (1 - 0.6 * dust))[:, None] * col(0.0016, 0.0016, 0.0021).T \
        + (heart * (1 - 0.7 * dust))[:, None] * col(0.0032, 0.0024, 0.0016).T
    mw = mw.reshape(h2, w2, 3)
    # Enlarge, wrapping round.
    r = np.clip((np.arange(H) + 0.5) / 2 - 0.5, 0, h2 - 1.001)
    c = (np.arange(W) + 0.5) / 2 - 0.5
    rr, cc = np.meshgrid(r, c, indexing="ij")
    return bilinear(mw, rr, cc)


def stars():
    """Stars even over the sphere, few bright and many faint, each a dot round on the sphere."""
    out = np.zeros((H, W, 3), np.float32)
    g = rng(30)
    count = 12000
    v = g.normal(size=(count, 3))
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    lat = np.degrees(np.arcsin(v[:, 1]))
    lon = np.degrees(np.arctan2(v[:, 2], v[:, 0])) % 360
    mag = g.pareto(2.3, count) + 1
    b = np.minimum(0.0045 * mag ** 1.5, 0.25)
    temp = g.random(count)
    tint = np.stack([np.interp(temp, [0, 0.15, 0.6, 1], [0.70, 0.85, 1.00, 1.00]),
                     np.interp(temp, [0, 0.15, 0.6, 1], [0.80, 0.90, 0.97, 0.82]),
                     np.interp(temp, [0, 0.15, 0.6, 1], [1.00, 1.00, 0.92, 0.62])], 1).astype(np.float32)
    row, colm = (90 - lat) / PX - 0.5, lon / PX - 0.5
    cosl = np.maximum(np.cos(np.radians(lat)), 0.02)
    sig = 0.05 + 0.025 * np.minimum(b / 0.1, 1)
    span = np.minimum(np.ceil(3 * sig / PX / cosl).astype(int) + 1, W // 2)
    for s in np.unique(np.minimum(2 ** np.ceil(np.log2(span)), W // 2).astype(int)):
        pick = np.minimum(2 ** np.ceil(np.log2(span)), W // 2).astype(int) == s
        r0 = np.floor(row[pick]).astype(int)[:, None, None] + np.arange(-2, 4)[None, :, None]
        c0 = np.floor(colm[pick]).astype(int)[:, None, None] + np.arange(-s, s + 1)[None, None, :]
        dy = (r0 - row[pick][:, None, None]) * PX
        dx = (((c0 - colm[pick][:, None, None]) * PX + 180) % 360 - 180) * cosl[pick][:, None, None]
        spot = b[pick][:, None, None] * np.exp(-(dy * dy + dx * dx) / (2 * sig[pick][:, None, None] ** 2))
        ok = (r0 >= 0) & (r0 < H)
        r0, c0 = np.broadcast_arrays(r0, c0)
        idx = (np.clip(r0, 0, H - 1) * W + c0 % W)[np.broadcast_to(ok, r0.shape)]
        val = (spot[..., None] * tint[pick][:, None, None, :])[np.broadcast_to(ok, r0.shape)]
        for ch in range(3):
            np.add.at(out[..., ch].reshape(-1), idx, val[:, ch])
    return out


def sun_glare(img):
    """The sun's disc and its glare, over everything."""
    la, lo = np.radians(90 - (np.arange(H) + 0.5) * PX)[:, None], np.radians(LON)[None, :]
    c = np.cos(la) * np.cos(lo) * SUN[0] + np.sin(la) * SUN[1] + np.cos(la) * np.sin(lo) * SUN[2]
    g = np.degrees(np.arccos(np.clip(c, -1, 1))).astype(np.float32)
    disc = smoothstep(0.42, 0.34, g) * (1 - 0.35 * (g / 0.4) ** 2)
    glare = 0.14 * np.exp(-g / 0.8) + 0.03 * np.exp(-g / 3.0) + 0.005 * np.exp(-g / 12.0)
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
    sun_lut()                                                      # once, before the workers fork
    img = stars() + milky_way()
    first = int(np.ceil((90 + TOP_DIP - 0.2) / PX - 0.5))          # the first row the air reaches
    limb = (90 + DIP) / PX
    fine = [r for r in range(first, H) if r + 0.5 < limb + 0.6 / PX]   # the air's band, 4 rows to a pixel
    coarse = [r for r in range(first, H) if r not in set(fine)]
    tasks = [(np.array(fine[i:i + 4]), 4) for i in range(0, len(fine), 4)]
    tasks += [(np.array(coarse[i:i + 16]), 1) for i in range(0, len(coarse), 16)]
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
