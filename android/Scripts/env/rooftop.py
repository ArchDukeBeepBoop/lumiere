"""Lumiere's rooftop: a city roof garden at night, the towers all round, modelled and lit, its light baked.

    blender-env/bin/python rooftop.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

You on a deep outdoor sofa on a timber deck high over the city (the sky's
towers and their lights); the screen hangs 16 m out over the street. A low
glass parapet ahead keeps the city in view; round you a water tower on steel
legs, rooftop plant and vents, planters of grasses, a bar cart, festoon
lights strung overhead on posts, a fire table glowing beside you.

Frame: you at the origin on the deck (y = 0), x to your left, z ahead.
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

AHEAD, BEHIND, HALF = 3.2, -9.0, 6.0


def materials():
    M = {}
    M["deck"] = textured("rdeck", (0.32, 0.22, 0.14), (0.22, 0.14, 0.08), "wood", scale=1.5, rough=0.6)
    M["roof"] = textured("rroof", (0.20, 0.20, 0.21), (0.13, 0.13, 0.14), "carpet", scale=3, rough=0.9)
    M["parapet"] = textured("rparapet", (0.38, 0.33, 0.30), (0.28, 0.24, 0.22), "carpet", scale=2, rough=0.9)
    M["steel"] = material("rsteel", (0.18, 0.18, 0.19), rough=0.4)
    M["glass"] = material("rglass", (0.25, 0.30, 0.32), rough=0.05)
    M["tank"] = textured("tank", (0.30, 0.20, 0.13), (0.20, 0.13, 0.08), "wood", scale=1.2, rough=0.8)
    M["vent"] = material("vent", (0.42, 0.43, 0.44), rough=0.5, metal=0.5)
    M["cushion"] = textured("rcushion", (0.36, 0.36, 0.34), (0.28, 0.28, 0.26), "cloth", scale=8, rough=0.95)
    M["throw"] = textured("rthrow", (0.55, 0.30, 0.12), (0.40, 0.20, 0.08), "carpet", scale=6, rough=1)
    M["grass"] = textured("rgrass", (0.25, 0.30, 0.15), (0.15, 0.18, 0.08), "cloth", scale=10, rough=0.9)
    M["planter"] = material("rplanter", (0.08, 0.08, 0.085), rough=0.6)
    M["bulb"] = glow("festoon", (1.0, 0.78, 0.45))
    M["fire"] = glow("rfire", (1.0, 0.55, 0.2))
    M["red"] = glow("beacon", (1.0, 0.1, 0.08))
    return M


def build(M):
    ground, things, glows = [], [], []
    r = random.Random(5)
    z = AHEAD
    while z > BEHIND:
        ground.append(box("board", (-HALF, -0.05, z - 0.14), (HALF, 0.0, z), M["deck"], bevel=0.004, segments=1))
        z -= 0.15
    ground.append(box("roofslab", (-HALF - 3, -0.35, BEHIND - 6), (HALF + 3, -0.05, AHEAD + 1.0), M["roof"]))
    # The parapet: concrete round the edge, glass ahead so the street stays in view.
    ground.append(box("lip", (-HALF - 3, -0.35, AHEAD + 1.0), (HALF + 3, 0.25, AHEAD + 1.3), M["parapet"], bevel=0.02, segments=2))
    things.append(box("glassrail", (-HALF - 3, 0.25, AHEAD + 1.12), (HALF + 3, 1.0, AHEAD + 1.16), M["glass"]))
    things.append(box("handrail", (-HALF - 3, 1.0, AHEAD + 1.08), (HALF + 3, 1.04, AHEAD + 1.2), M["steel"]))
    for side in (1, -1):
        x0, x1 = sorted((side * (HALF + 3), side * (HALF + 3.3)))
        ground.append(box("sidewall", (x0, -0.35, BEHIND - 6), (x1, 1.05, AHEAD + 1.3), M["parapet"], bevel=0.02, segments=2))
    # Your sofa and a fire table on your right.
    things.append(box("sofabase", (-1.3, 0.05, -0.55), (1.3, 0.38, 0.35), M["steel"], bevel=0.03, segments=2))
    things.append(box("sofaseat", (-1.2, 0.38, -0.45), (1.2, 0.52, 0.32), M["cushion"], bevel=0.06, segments=3))
    things.append(tilt(box("sofaback", (-1.25, 0.4, -0.6), (1.25, 0.95, -0.4), M["cushion"], bevel=0.07, segments=3), 10, (0.45, -0.5)))
    for side in (1, -1):
        x0, x1 = sorted((side * 1.2, side * 1.35))
        things.append(box("sofaarm", (x0, 0.05, -0.55), (x1, 0.66, 0.35), M["cushion"], bevel=0.05, segments=3))
    things.append(box("throw", (0.2, 0.52, -0.35), (0.9, 0.55, 0.3), M["throw"], bevel=0.01, segments=1))
    things.append(box("firetable", (-2.6, 0.0, -0.5), (-1.7, 0.42, 0.4), M["parapet"], bevel=0.02, segments=2))
    glows.append(box("fire", (-2.45, 0.42, -0.35), (-1.85, 0.46, 0.25), M["fire"]))
    point("fire", (-2.15, 0.7, -0.05), 90, (1.0, 0.55, 0.22), radius=0.2)
    # Planters of grasses along the sides.
    for side in (1, -1):
        for pz in (1.8, -1.8, -4.5):
            px = side * (HALF - 0.5)
            things.append(box("planter", (px - 0.4, 0.0, pz - 0.9), (px + 0.4, 0.6, pz + 0.9), M["planter"], bevel=0.02, segments=2))
            for k in range(40):
                gx, gz = px + r.uniform(-0.3, 0.3), pz + r.uniform(-0.8, 0.8)
                things.append(rod("blade", (gx, 0.6, gz), (gx + r.uniform(-0.2, 0.2), 0.6 + r.uniform(0.5, 1.0), gz + r.uniform(-0.2, 0.2)), 0.012, M["grass"], sides=3))
    # The water tower on steel legs behind, a beacon on top; vents and an AC unit.
    tx, tz = 3.5, -7.5
    for (lx, lz) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        things.append(rod("leg", (tx + lx * 1.2, 0, tz + lz * 1.2), (tx + lx * 1.0, 3.0, tz + lz * 1.0), 0.06, M["steel"], sides=8))
    things.append(cylinder("tank", tx, tz, 1.5, 3.0, 6.0, M["tank"], segments=32))
    for y in (3.4, 4.4, 5.4):
        things.append(cylinder("hoop", tx, tz, 1.53, y, y + 0.06, M["steel"], segments=32))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=1.6, radius2=0.05, depth=1.0)
    bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90), 4, 'X'), verts=bm.verts)
    bmesh.ops.translate(bm, vec=P(tx, 6.5, tz), verts=bm.verts)
    things.append(_mesh_object("tankroof", bm, M["steel"]))
    glows.append(cylinder("beacon", tx, tz, 0.08, 7.0, 7.15, M["red"], segments=10))
    things.append(box("ac", (-5.5, 0.0, -8.0), (-3.0, 1.4, -6.5), M["vent"], bevel=0.04, segments=2))
    things.append(cylinder("fan", -4.25, -7.25, 0.55, 1.4, 1.45, M["steel"], segments=24))
    for (vx, vz) in ((-1.5, -8.0), (0.5, -8.5)):
        things.append(cylinder("vent", vx, vz, 0.2, 0.0, 1.2, M["vent"], segments=16))
        things.append(cylinder("ventcap", vx, vz, 0.3, 1.2, 1.3, M["vent"], segments=16))
    # Festoon lights in a zigzag overhead on posts.
    posts = [(HALF - 0.2, 2.5), (-HALF + 0.2, 0.0), (HALF - 0.2, -2.5), (-HALF + 0.2, -5.0), (HALF - 0.2, -7.5)]
    for (px, pz) in posts:
        things.append(cylinder("fpost", px, pz, 0.05, 0.0, 3.2, M["steel"], segments=8))
    for (ax, az), (bx, bz) in zip(posts, posts[1:]):
        n = 14
        for k in range(n):
            f = (k + 0.5) / n
            sag = 0.45 * math.sin(math.pi * f)
            x, z = ax + (bx - ax) * f, az + (bz - az) * f
            glows.append(cylinder("bulb", x, z, 0.04, 3.0 - sag, 3.09 - sag, M["bulb"], segments=8))
        point("festoon", ((ax + bx) / 2, 2.6, (az + bz) / 2), 45, (1.0, 0.75, 0.45), radius=0.3)
    return ground, things, glows


def light(s):
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.06, 0.10, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    sun("cityglow", 0.12, (1.0, 0.7, 0.45), (0, 0.15, 1), angle=30)


if __name__ == "__main__":
    main("rooftop", materials, build, light, exposure=1.3)
