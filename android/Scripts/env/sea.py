"""Lumiere under the sea: a sandy clearing in a kelp forest, modelled and lit, its light baked.

    blender-env/bin/python sea.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

You on a flat rock in a sandy clearing (the sea itself is the sky's picture);
the screen hangs 13 m out in the blue. Round you: rippled sand, boulders
crusted with coral and sponges, kelp rising in tall swaying ribbons, an old
anchor half buried, shells and starfish. Lit from the surface: a soft blue-
green light from above and the screen's own glow.

Frame: you at the origin on the seabed (y = 0), x to your left, z ahead.
"""
import sys
import os
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from openair import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402,F401
import bmesh  # noqa: E402
from cinema import rod  # noqa: E402


def materials():
    M = {}
    M["sand"] = textured("sand", (0.62, 0.58, 0.46), (0.48, 0.44, 0.34), "carpet", scale=3, rough=1, bump=0.2)
    M["rock"] = textured("rock", (0.30, 0.30, 0.28), (0.16, 0.17, 0.16), "carpet", scale=1.5, rough=1, bump=0.4)
    M["kelp"] = textured("kelp", (0.30, 0.32, 0.08), (0.20, 0.20, 0.05), "cloth", scale=4, rough=0.8)
    M["coral"] = [material("coral%d" % i, c, rough=0.9) for i, c in enumerate(
        [(0.85, 0.35, 0.30), (0.90, 0.55, 0.20), (0.55, 0.25, 0.55), (0.85, 0.75, 0.40), (0.30, 0.55, 0.60)])]
    M["iron"] = textured("iron", (0.22, 0.12, 0.07), (0.12, 0.08, 0.06), "carpet", scale=4, rough=1)
    M["shell"] = material("shell", (0.85, 0.78, 0.68), rough=0.5)
    return M


def boulder(M, x, z, rad, seed, flat=1.0):
    r = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=rad)
    for v in bm.verts:
        v.co *= 1 + 0.18 * math.sin(v.co.x * 5 + seed) * math.cos(v.co.y * 4 + seed) + r.uniform(-0.05, 0.05)
    bmesh.ops.scale(bm, vec=(1.0, 1.0, 0.6 * flat), verts=bm.verts)
    bmesh.ops.translate(bm, vec=P(x, rad * 0.25 * flat, z), verts=bm.verts)
    return _mesh_object("boulder", bm, M["rock"], smooth=True)


def build(M):
    ground, things, glows = [], [], []
    r = random.Random(11)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=80, y_segments=80, size=1.0)
    for v in bm.verts:
        x, z = v.co.x * 40, v.co.y * 40
        d = math.hypot(x, z - 4)
        v.co = Vector(P(x, 0.03 * math.sin(x * 2.2 + z * 0.8) + max(0, d - 14) * 0.25, z))
    ground.append(_mesh_object("seabed", bm, M["sand"], smooth=True))
    # Your rock seat.
    things.append(boulder(M, 0, -0.1, 0.75, 1, flat=0.7))
    # Boulders and coral round the clearing, low ahead, taller to the sides and behind.
    spots = []
    for i in range(26):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(4, 13)
        x, z = d * math.cos(a), d * math.sin(a)
        if z > 2 and abs(x) < 6: continue
        spots.append((x, z))
        rad = r.uniform(0.5, 1.6)
        things.append(boulder(M, x, z, rad, i + 2))
        for k in range(r.randint(3, 7)):
            cx, cz = x + r.uniform(-rad, rad) * 0.7, z + r.uniform(-rad, rad) * 0.7
            col = r.choice(M["coral"])
            base = rad * 0.4
            if r.random() < 0.5:
                # Branching coral.
                for b in range(5):
                    things.append(rod("branch", (cx, base, cz), (cx + r.uniform(-0.3, 0.3), base + r.uniform(0.3, 0.7), cz + r.uniform(-0.3, 0.3)), 0.035, col, sides=6))
            else:
                # A round brain coral or sponge.
                bmc = bmesh.new()
                bmesh.ops.create_icosphere(bmc, subdivisions=2, radius=r.uniform(0.15, 0.35))
                bmesh.ops.translate(bmc, vec=P(cx, base + 0.1, cz), verts=bmc.verts)
                things.append(_mesh_object("brain", bmc, col, smooth=True))
    # Kelp: tall ribbons from the sand to the light, swaying.
    for i in range(70):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(5, 22)
        x, z = d * math.cos(a), d * math.sin(a)
        if z > 3 and abs(x) < 8: continue
        h = r.uniform(5, 14)
        bm = bmesh.new()
        segs = 14
        prev = None
        ph = r.uniform(0, 6)
        for s in range(segs + 1):
            f = s / segs
            sx = x + 0.4 * math.sin(f * 3 + ph) * f
            w = 0.12 + 0.08 * math.sin(f * 9 + ph)
            v1 = bm.verts.new(P(sx - w, f * h, z))
            v2 = bm.verts.new(P(sx + w, f * h, z + 0.02))
            if prev: bm.faces.new((prev[0], prev[1], v2, v1))
            prev = (v1, v2)
        k = _mesh_object("kelp", bm, M["kelp"], smooth=True)
        k.rotation_euler[2] = r.uniform(0, math.pi)
        things.append(k)
    # The old anchor, half buried on your left, and its chain.
    ax, az = 3.2, 1.5
    things.append(rod("shank", (ax, 0.0, az), (ax + 0.3, 1.6, az - 0.4), 0.07, M["iron"], sides=8))
    things.append(rod("stock", (ax - 0.5, 1.4, az - 0.3), (ax + 1.0, 1.55, az - 0.45), 0.05, M["iron"], sides=8))
    for side in (1, -1):
        things.append(rod("fluke", (ax, 0.05, az), (ax + side * 0.6, 0.4, az + 0.1), 0.06, M["iron"], sides=8))
    for c in range(14):
        cx, cz = ax - 0.3 * c, az - 0.5 - 0.25 * c
        bmc = bmesh.new()
        bmesh.ops.create_cone(bmc, cap_ends=False, segments=10, radius1=0.08, radius2=0.08, depth=0.04)
        bmesh.ops.translate(bmc, vec=P(cx, 0.04, cz), verts=bmc.verts)
        things.append(_mesh_object("chain", bmc, M["iron"]))
    # Shells and starfish scattered about.
    for i in range(30):
        x, z = r.uniform(-5, 5), r.uniform(-5, 4)
        if math.hypot(x, z) < 1.0: continue
        bmc = bmesh.new()
        bmesh.ops.create_icosphere(bmc, subdivisions=1, radius=r.uniform(0.04, 0.09))
        bmesh.ops.scale(bmc, vec=(1, 1, 0.4), verts=bmc.verts)
        bmesh.ops.translate(bmc, vec=P(x, 0.03, z), verts=bmc.verts)
        things.append(_mesh_object("shell", bmc, M["shell"] if i % 3 else M["coral"][1], smooth=True))
    return ground, things, glows


def light(s):
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.18, 0.28, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    sun("surface", 1.6, (0.55, 0.85, 0.95), (0.2, 1, 0.3), angle=25)
    area("screen", (0, 2.4, 13), 9.0, 400, (0.7, 0.85, 1.0), aim=(0, 0.5, 0), size_y=5)


if __name__ == "__main__":
    main("sea", materials, build, light, exposure=0.9)
