"""Lumiere's Space: an equirect starfield, 4096 x 2048, for a skybox on a Quest.

Stars spread evenly over the sphere, brightness on a power law (few bright,
many faint), colours from blue-white to amber as real stars run, each a soft
dot sized by brightness; a faint Milky Way band along a tilted great circle,
broken by darker dust. Deterministic (seeded), so a rebuild is the same sky.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

W, H = 4096, 2048
rng = np.random.default_rng(1729)
sky = np.zeros((H, W, 3), np.float32)

# The Milky Way: distance from a tilted great circle, a soft glow with dust lanes.
lon = (np.arange(W) + 0.5) / W * 2 * np.pi
lat = np.pi / 2 - (np.arange(H) + 0.5) / H * np.pi
LON, LAT = np.meshgrid(lon, lat)
x, y, z = np.cos(LAT) * np.cos(LON), np.sin(LAT), np.cos(LAT) * np.sin(LON)
tilt = np.radians(62)
n = np.array([0.0, np.cos(tilt), np.sin(tilt)])          # the band's pole
d = np.abs(x * n[0] + y * n[1] + z * n[2])               # sin of distance from the band
glow = np.exp(-(d / 0.16) ** 2)
noise = np.zeros((H // 8, W // 8), np.float32)
for octave, amp in [(1, 1.0), (2, 0.5), (4, 0.25), (8, 0.125)]:
    small = rng.random((max(2, H // 64 * octave // 4), max(4, W // 64 * octave // 4))).astype(np.float32)
    noise += amp * np.array(Image.fromarray((small * 255).astype(np.uint8)).resize((W // 8, H // 8), Image.BICUBIC), np.float32) / 255
noise = np.array(Image.fromarray(np.clip(noise / 1.9 * 255, 0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32) / 255
dust = np.clip((noise - 0.42) * 2.6, 0, 1)
band = glow * (0.5 + 0.5 * noise) * (1 - 0.8 * dust)
core = np.exp(-(d / 0.07) ** 2) * (0.6 + 0.4 * noise) * (1 - 0.85 * dust)
sky += band[..., None] * np.array([0.085, 0.080, 0.095], np.float32)
sky += core[..., None] * np.array([0.075, 0.060, 0.045], np.float32)   # a warmer, denser heart

# Stars: even over the sphere, more of them in the band.
def stars(count, band_bias):
    u = rng.random(count)
    v = np.arccos(1 - 2 * rng.random(count)) / np.pi       # even in solid angle
    px, py = (u * W).astype(int) % W, np.clip((v * H).astype(int), 0, H - 1)
    keep = rng.random(count) < (1 - band_bias + band_bias * glow[py, px])
    return px[keep], py[keep]

px, py = stars(26000, 0.6)
mag = rng.pareto(2.2, px.size) + 1                         # few bright, many faint
bright = np.clip(0.22 * mag, 0.10, 1.8)
temp = rng.random(px.size)
colour = np.stack([
    np.interp(temp, [0, 0.15, 0.6, 1], [0.70, 0.85, 1.00, 1.00]),
    np.interp(temp, [0, 0.15, 0.6, 1], [0.80, 0.90, 0.97, 0.82]),
    np.interp(temp, [0, 0.15, 0.6, 1], [1.00, 1.00, 0.92, 0.62]),
], 1).astype(np.float32)
points = np.zeros((H, W, 3), np.float32)
np.add.at(points, (py, px), colour * bright[:, None])
# A soft dot per star: a tight blur for all, a wider halo for the brightest.
img = Image.fromarray(np.clip(points * 255, 0, 255).astype(np.uint8))
core = np.array(img.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255 * 3.2
halo = np.array(img.filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255 * 1.4
sky += core + halo * (points.max(2, keepdims=True) > 0.6)
# Horizontal stretch toward the poles is the equirect's own; the skybox undoes it.
out = np.clip(sky, 0, 1) ** (1 / 1.15)
Image.fromarray((out * 255).astype(np.uint8)).save(sys.argv[1], quality=90, optimize=True)
print("stars", px.size)
