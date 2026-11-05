"""Lumiere's drive-in: a summer night at the pictures from the bed of a pickup, modelled and lit, its light baked.

    blender-env/bin/python drivein.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

You sit in the bed of an old pickup on blankets and cushions, its tailgate
down toward the screen 30 m out (the screen itself is the film's panel); the
lot falls away in gravel rows to the screen, cars parked nose-to-screen low
enough that every roof clears your line, speaker posts between them, the
projection booth and snack bar behind you glowing, a string of bulbs along
the fence. Lit by a warm moon low behind and the booth's light.

Frame: you at the origin on the truck's bed (y = 0, the lot 0.9 below), x to your left, z ahead.
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

LOT = -0.9


def materials():
    M = {}
    M["gravel"] = textured("gravel", (0.20, 0.19, 0.17), (0.11, 0.10, 0.09), "carpet", scale=3, rough=1, bump=0.3)
    M["paint"] = material("truckpaint", (0.28, 0.06, 0.05), rough=0.35)
    M["bed"] = textured("bedwood", (0.40, 0.27, 0.15), (0.26, 0.16, 0.08), "wood", scale=2, rough=0.7)
    M["chrome"] = material("chrome", (0.55, 0.55, 0.56), rough=0.2, metal=0.8)
    M["tyre"] = material("tyre", (0.02, 0.02, 0.02), rough=0.8)
    M["blanket"] = textured("blanket", (0.55, 0.12, 0.10), (0.85, 0.80, 0.70), "cloth", scale=6, rough=1)
    M["cushion"] = textured("dcushion", (0.20, 0.32, 0.45), (0.14, 0.24, 0.34), "cloth", scale=8, rough=1)
    M["glass"] = material("dglass", (0.05, 0.06, 0.07), rough=0.1)
    M["post"] = material("post", (0.15, 0.16, 0.15), rough=0.6)
    M["wall"] = textured("booth", (0.70, 0.66, 0.58), (0.60, 0.56, 0.48), "cloth", scale=2, rough=0.9)
    M["roof"] = material("boothroof", (0.12, 0.10, 0.09), rough=0.8)
    M["cars"] = [material("car%d" % i, c, rough=0.4) for i, c in enumerate(
        [(0.10, 0.20, 0.32), (0.50, 0.45, 0.35), (0.06, 0.06, 0.07), (0.32, 0.30, 0.10), (0.30, 0.32, 0.33), (0.15, 0.25, 0.18)])]
    M["bulb"] = glow("bulb", (1.0, 0.78, 0.45))
    M["window"] = glow("boothwin", (1.0, 0.82, 0.55))
    M["neon"] = glow("neon", (1.0, 0.25, 0.35))
    return M


def car(M, x, z, mat, r):
    """A low saloon parked nose to the screen, its roof under 1.45 m off the lot."""
    y0 = LOT
    p = [box("body", (x - 0.9, y0 + 0.3, z - 2.4), (x + 0.9, y0 + 0.85, z + 2.4), mat, bevel=0.12, segments=3),
         box("cabin", (x - 0.78, y0 + 0.85, z - 1.2), (x + 0.78, y0 + 1.35, z + 0.9), M["glass"], bevel=0.12, segments=3),
         box("roof", (x - 0.8, y0 + 1.3, z - 1.0), (x + 0.8, y0 + 1.40, z + 0.7), mat, bevel=0.05, segments=2)]
    for (wx, wz) in ((x - 0.85, z - 1.5), (x + 0.85, z - 1.5), (x - 0.85, z + 1.5), (x + 0.85, z + 1.5)):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.33, radius2=0.33, depth=0.22)
        bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90), 4, 'Y'), verts=bm.verts)
        bmesh.ops.translate(bm, vec=P(wx, y0 + 0.33, wz), verts=bm.verts)
        p.append(_mesh_object("wheel", bm, M["tyre"], smooth=True))
    return p


def build(M):
    ground, things, glows = [], [], []
    r = random.Random(3)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=40, y_segments=40, size=1.0)
    for v in bm.verts:
        x, z = v.co.x * 60, v.co.y * 60 + 10
        v.co = Vector(P(x, LOT + 0.04 * math.sin(x * 0.7) * math.cos(z * 0.5) - (0.01 * max(0, z) if z > 0 else 0), z))
    ground.append(_mesh_object("lot", bm, M["gravel"], smooth=True))
    # Your pickup: its bed round you, cab behind, tailgate down toward the screen.
    bx, bz0, bz1 = 0.85, -1.5, 0.75
    t = []
    t.append(box("bedfloor", (-bx, -0.08, bz0), (bx, 0.0, bz1), M["bed"]))
    for side in (1, -1):
        x0, x1 = sorted((side * bx, side * (bx + 0.08)))
        t.append(box("bedside", (x0, -0.5, bz0), (x1, 0.5, bz1), M["paint"], bevel=0.03, segments=2))
        t.append(box("fender", (side * (bx + 0.08) - (0.0 if side > 0 else 0.22), -0.75, -0.9) if side > 0 else (-bx - 0.30, -0.75, -0.9),
                     (side * (bx + 0.30), -0.15, 0.3) if side > 0 else (-bx - 0.08, -0.15, 0.3), M["paint"], bevel=0.1, segments=3))
    t.append(box("tailgate", (-bx, -0.10, bz1), (bx, -0.02, bz1 + 0.5), M["paint"], bevel=0.02, segments=2))
    t.append(box("cab", (-bx - 0.05, -0.5, bz0 - 1.6), (bx + 0.05, 1.25, bz0), M["paint"], bevel=0.12, segments=3))
    t.append(box("rearwin", (-0.6, 0.55, bz0 - 0.02), (0.6, 1.05, bz0 + 0.01), M["glass"]))
    t.append(box("hood", (-bx - 0.05, -0.5, bz0 - 3.4), (bx + 0.05, 0.35, bz0 - 1.6), M["paint"], bevel=0.12, segments=3))
    t.append(box("bumper", (-bx - 0.1, -0.55, bz1 - 0.05), (bx + 0.1, -0.42, bz1 + 0.05), M["chrome"]))
    things += t
    # Blankets and cushions in the bed; a cooler; a popcorn bucket.
    things.append(box("blanket", (-bx + 0.05, 0.0, bz0 + 0.05), (bx - 0.05, 0.08, bz1 - 0.05), M["blanket"], bevel=0.04, segments=2))
    things.append(tilt(box("backrest", (-0.7, 0.05, bz0 + 0.05), (0.7, 0.75, bz0 + 0.3), M["cushion"], bevel=0.1, segments=3), 15, (0.05, bz0 + 0.2)))
    things.append(box("pillow", (0.25, 0.08, bz0 + 0.3), (0.65, 0.35, bz0 + 0.55), M["cushion"], bevel=0.1, segments=3))
    things.append(box("cooler", (-0.78, 0.08, -0.6), (-0.42, 0.42, -0.1), M["cars"][0], bevel=0.04, segments=2))
    things.append(cylinder("popcorn", 0.55, 0.2, 0.09, 0.08, 0.32, M["blanket"], segments=16))
    # Rows of cars ahead, nose to the screen, and speaker posts between.
    for row, z in enumerate((5.5, 11.0, 16.5)):
        for x in (-7.5, -4.5, 4.5, 7.5, -10.5, 10.5) + ((0.0,) if row else ()):
            if r.random() < 0.15: continue
            things += car(M, x + r.uniform(-0.2, 0.2), z + r.uniform(-0.3, 0.3), r.choice(M["cars"]), r)
        for x in (-6.0, -3.0, 3.0, 6.0, 9.0, -9.0):
            things.append(cylinder("spkpost", x, z - 2.4, 0.04, LOT, LOT + 1.1, M["post"], segments=8))
            things.append(box("speaker", (x - 0.12, LOT + 1.0, z - 2.45), (x + 0.12, LOT + 1.22, z - 2.35), M["post"], bevel=0.02, segments=2))
    for side in (1, -1):
        things += car(M, side * 3.0, 0.2, r.choice(M["cars"]), r)
        things += car(M, side * 6.0, -0.4, r.choice(M["cars"]), r)
    # The booth and snack bar behind, windows aglow; a neon sign on its roof.
    things.append(box("booth", (-6, LOT, -16), (6, LOT + 3.4, -11), M["wall"], bevel=0.05, segments=2))
    things.append(box("boothroof", (-6.4, LOT + 3.4, -16.3), (6.4, LOT + 3.65, -10.6), M["roof"]))
    for x in (-4.5, -1.5, 1.5, 4.5):
        glows.append(box("boothwin", (x - 1.0, LOT + 1.0, -11.02), (x + 1.0, LOT + 2.3, -10.98), M["window"]))
    glows.append(box("neon", (-3.0, LOT + 3.8, -13.6), (3.0, LOT + 4.4, -13.5), M["neon"]))
    area("booth", (0, LOT + 1.7, -10.7), 9.0, 300, (1.0, 0.8, 0.5), aim=(0, LOT, 0), size_y=1.4)
    # A string of bulbs on poles along the side fences.
    for side in (1, -1):
        poles = [(-12 + 8 * i) for i in range(6)]
        for pz in poles:
            things.append(cylinder("pole", side * 13, pz, 0.06, LOT, LOT + 4.0, M["post"], segments=8))
        for a, b in zip(poles, poles[1:]):
            for k in range(8):
                f = (k + 0.5) / 8
                sag = 0.5 * math.sin(math.pi * f)
                glows.append(cylinder("bulb", side * 13, a + (b - a) * f, 0.05, LOT + 3.85 - sag, LOT + 3.95 - sag, M["bulb"], segments=8))
            point("bulbs", (side * 12.8, LOT + 3.6, (a + b) / 2), 60, (1.0, 0.75, 0.45), radius=0.2)
    return ground, things, glows


def light(s):
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.04, 0.09, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sun("moon", 0.35, (0.75, 0.80, 1.0), (0.4, 0.5, -1), angle=1)


if __name__ == "__main__":
    main("drivein", materials, build, light, exposure=1.3, info={"lot": LOT})
