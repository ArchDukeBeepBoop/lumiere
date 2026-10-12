"""Lumiere's cabin: a timber great room by the lake at dusk, modelled and lit, its light baked.

    blender-env/bin/python cabin.py preview OUT     lit in Cycles, from the sofa at each size
    blender-env/bin/python cabin.py bake OUT        baked to OUT/cabin.glb and OUT/cabin_sofa.glb (+ cabin.json)
    QUALITY=quick ...                                 small atlases and few samples

The room stands still round its screen, 5.5 m across on a wall of dark
timber battens; the five sizes are how near the sofa is (CabinRoom on the
Quest), so the sofa, its rug, coffee table and side tables are a model of
their own that comes with you. On your left a stone chimney breast with a
fire, its mantel and candles, logs stacked in a niche; on your right floor-
to-ceiling glass between oak piers, the lake at dusk beyond (the sky); a
timber ceiling on exposed beams; tall speakers either side of the screen;
behind you a wall of books. Lit by the fire, two lamps, low downlights and
the dusk through the glass.

Frame as cinema.py's: x to your left, y up, z toward the screen; the origin
on the floor under the screen's middle, the screen's face at z = 0.
"""
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from envkit import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402,F401
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402
from cinema import rod, shifted  # noqa: E402

SCREEN_W = 5.5
SCREEN_H = SCREEN_W * 9 / 16
SCREEN_MID = 1.72
SCREEN_BOTTOM = SCREEN_MID - SCREEN_H / 2
HALF = 4.6                  # side walls' faces
BACK = -9.4                 # the back wall's face (the farthest sofa is 5.3 m out, its back 0.8 behind you)
CEILING = 4.4
WALL_FACE = 0.06            # the batten wall just behind the screen
DEGREES = [55, 70, 85, 100, 115]
DISTANCES = [SCREEN_W / (2 * math.tan(math.radians(d / 2))) for d in DEGREES]
DEFAULT = 2
EYE = 1.15

QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)
WARM = (1.0, 0.66, 0.38)
LAMP = (1.0, 0.74, 0.46)
DUSK = (0.45, 0.58, 1.0)


def materials():
    M = {}
    M["oak"] = textured("oak", (0.42, 0.27, 0.15), (0.30, 0.18, 0.09), "wood", scale=1.4, rough=0.5)
    M["batten"] = textured("batten", (0.11, 0.07, 0.045), (0.07, 0.042, 0.026), "wood", scale=2.0, rough=0.6)
    M["walnut"] = textured("walnut", (0.16, 0.085, 0.045), (0.09, 0.045, 0.022), "wood", scale=1.2, rough=0.45)
    M["beam"] = textured("beam", (0.30, 0.19, 0.11), (0.20, 0.12, 0.06), "wood", scale=0.8, rough=0.6)
    M["plaster"] = textured("plaster", (0.46, 0.40, 0.33), (0.40, 0.35, 0.29), "cloth", scale=2, rough=0.9)
    M["stone"] = textured("stone", (0.36, 0.33, 0.29), (0.18, 0.16, 0.14), "carpet", scale=2.2, rough=0.9, bump=0.3)
    M["slate"] = material("slate", (0.06, 0.06, 0.065), rough=0.7)
    M["soot"] = material("soot", (0.01, 0.009, 0.008), rough=1)
    M["rug"] = textured("rug", (0.55, 0.50, 0.42), (0.40, 0.35, 0.28), "carpet", scale=3.0, rough=1)
    M["leather"] = textured("leather", (0.42, 0.19, 0.08), (0.30, 0.12, 0.05), "cloth", scale=4, rough=0.55)
    M["linen"] = textured("linen", (0.70, 0.66, 0.58), (0.58, 0.54, 0.46), "cloth", scale=8, rough=0.9)
    M["wool"] = textured("wool", (0.48, 0.18, 0.12), (0.34, 0.12, 0.08), "cloth", scale=6, rough=1)
    M["black"] = material("black", (0.012, 0.012, 0.012), rough=0.6)
    M["brass"] = material("brass", (0.45, 0.30, 0.11), rough=0.35)
    M["ceramic"] = material("ceramic", (0.72, 0.70, 0.66), rough=0.3)
    M["green"] = textured("leafy", (0.06, 0.16, 0.05), (0.03, 0.09, 0.03), "cloth", scale=10, rough=0.8)
    M["terracotta"] = material("terracotta", (0.45, 0.20, 0.10), rough=0.8)
    M["mullion"] = material("mullion", (0.035, 0.032, 0.03), rough=0.5)
    M["books"] = [material("book%d" % i, c, rough=0.7) for i, c in enumerate([
        (0.35, 0.08, 0.06), (0.10, 0.18, 0.30), (0.55, 0.45, 0.25), (0.12, 0.25, 0.14), (0.62, 0.58, 0.50),
        (0.20, 0.10, 0.22), (0.45, 0.30, 0.12), (0.08, 0.08, 0.09)])]
    M["screen"] = lamp("screen", (0.06, 0.06, 0.065))
    M["fire"] = glow("fire", (1.0, 0.55, 0.18))
    M["ember"] = glow("ember", (0.9, 0.25, 0.05))
    M["shade"] = lamp("shade", (1.0, 0.82, 0.58))
    M["flame"] = glow("candle", (1.0, 0.75, 0.40))
    M["down"] = lamp("down", (1.0, 0.92, 0.78))
    return M


def battens(objs, M, x0, x1, y0, y1, z, pitch=0.09, width=0.045, depth=0.05):
    """A wall of vertical timber battens over a dark backing at [z] (facing you)."""
    objs.append(box("backing", (x0, y0, z), (x1, y1, z + 0.05), M["black"]))
    x = x0 + pitch / 2
    while x < x1:
        objs.append(box("batten", (x - width / 2, y0, z - depth), (x + width / 2, y1, z), M["batten"]))
        x += pitch


def room(M):
    hall, left, right, glows = [], [], [], []
    # The oak floor, wide planks; the timber ceiling on exposed beams.
    planks = []
    x = -HALF
    i = 0
    while x < HALF:
        w = 0.24
        planks.append(box("plank", (x + 0.003, -0.05, BACK), (min(x + w, HALF) - 0.003, 0.0, WALL_FACE), M["oak"], bevel=0.004, segments=1))
        x += w; i += 1
    hall += planks
    hall.append(box("ceiling", (-HALF, CEILING, BACK), (HALF, CEILING + 0.1, WALL_FACE), M["batten"]))
    z = -0.9
    while z > BACK + 0.4:
        hall.append(box("beam", (-HALF, CEILING - 0.32, z - 0.12), (HALF, CEILING, z + 0.12), M["beam"], bevel=0.02, segments=2))
        z -= 2.1
    hall.append(box("ridge", (-0.14, CEILING - 0.4, BACK), (0.14, CEILING, WALL_FACE), M["beam"], bevel=0.02, segments=2))

    # The screen wall: battens floor to ceiling, the screen on them; tall speakers either side; a low shelf under it.
    battens(hall, M, -HALF, HALF, 0.0, CEILING, WALL_FACE)
    glows.append(box("screen", (-SCREEN_W / 2, SCREEN_BOTTOM, 0.005), (SCREEN_W / 2, SCREEN_BOTTOM + SCREEN_H, 0.02), M["screen"]))
    hall.append(box("bezel", (-SCREEN_W / 2 - 0.04, SCREEN_BOTTOM - 0.04, 0.02), (SCREEN_W / 2 + 0.04, SCREEN_BOTTOM + SCREEN_H + 0.04, 0.04), M["black"]))
    for side in (1, -1):
        cx = side * (SCREEN_W / 2 + 0.55)
        hall.append(box("speaker", (cx - 0.17, 0.0, -0.42), (cx + 0.17, 1.22, -0.08), M["walnut"], bevel=0.015, segments=2))
        hall.append(box("grille", (cx - 0.15, 0.08, -0.43), (cx + 0.15, 1.16, -0.42), M["black"]))
    hall.append(box("shelf", (-2.0, 0.0, -0.38), (2.0, 0.16, 0.0), M["walnut"], bevel=0.01, segments=2))

    # Left: the stone chimney breast with its fire, mantel and candles; logs in a niche beside it.
    cz0, cz1 = -4.2, -2.4
    xin = HALF - 0.7
    left.append(box("chimney", (xin, 0.0, cz0), (HALF, CEILING, cz1), M["stone"], bevel=0.02, segments=2))
    left.append(box("firebox", (xin - 0.01, 0.35, cz0 + 0.35), (xin + 0.35, 1.0, cz1 - 0.35), M["soot"]))
    left.append(box("hearth", (xin - 0.55, 0.0, cz0 - 0.15), (xin, 0.12, cz1 + 0.15), M["slate"], bevel=0.01, segments=1))
    left.append(box("mantel", (xin - 0.16, 1.3, cz0 - 0.1), (xin + 0.05, 1.4, cz1 + 0.1), M["beam"], bevel=0.015, segments=2))
    for i, z in enumerate((cz0 + 0.2, cz0 + 0.35, cz1 - 0.25)):
        h = (0.22, 0.16, 0.28)[i]
        left.append(cylinder("candle", xin - 0.07, z, 0.035, 1.4, 1.4 + h, M["ceramic"], segments=12))
        glows.append(cylinder("flame", xin - 0.07, z, 0.012, 1.4 + h, 1.4 + h + 0.05, M["flame"], segments=8))
    for k in range(5):
        left.append(rod("log", (xin - 0.05 - 0.05 * (k % 2), 0.42 + 0.07 * (k // 2), cz0 + 0.45), (xin + 0.2, 0.42 + 0.07 * (k // 2), cz1 - 0.45), 0.055, M["beam"]))
    glows.append(box("fire", (xin + 0.04, 0.4, cz0 + 0.5), (xin + 0.2, 0.75, cz1 - 0.5), M["fire"]))
    glows.append(box("embers", (xin + 0.02, 0.36, cz0 + 0.45), (xin + 0.25, 0.4, cz1 - 0.45), M["ember"]))
    point("fire", (xin - 0.25, 0.65, (cz0 + cz1) / 2), 180, (1.0, 0.5, 0.2), radius=0.25)
    point("fire_low", (xin - 0.05, 0.45, (cz0 + cz1) / 2), 80, (1.0, 0.4, 0.12), radius=0.2)
    # A log niche beside the breast, and plaster walls round it.
    nz0, nz1 = cz1 + 0.3, cz1 + 1.3
    left.append(box("niche", (HALF - 0.45, 0.0, nz0), (HALF, 1.5, nz1), M["soot"]))
    for row in range(5):
        for k in range(4):
            y = 0.1 + row * 0.14
            left.append(rod("logs", (HALF - 0.42, y, nz0 + 0.12 + k * 0.24), (HALF - 0.05, y, nz0 + 0.12 + k * 0.24), 0.065, M["beam"], sides=8))
    left.append(panel("leftwall", HALF + 0.1, -1, [(WALL_FACE, 0.0), (WALL_FACE, CEILING), (BACK, CEILING), (BACK, 0.0)], 0.1, M["plaster"]))
    left.append(box("framed", (HALF - 0.04, 1.5, -6.7), (HALF, 2.6, -5.1), M["walnut"], bevel=0.01, segments=1))
    left.append(box("canvas", (HALF - 0.05, 1.56, -6.64), (HALF - 0.04, 2.54, -5.16), M["linen"]))

    # Right: glass from floor to ceiling between oak piers, the dusk beyond; thin mullions across.
    piers = [WALL_FACE - 0.2, -2.0, -4.0, -6.0, -8.0, BACK + 0.2]
    for z in piers:
        right.append(box("pier", (-HALF - 0.1, 0.0, z - 0.15), (-HALF + 0.12, CEILING, z + 0.15), M["beam"], bevel=0.015, segments=2))
    for y in (0.35, 2.6):
        right.append(box("transom", (-HALF - 0.06, y - 0.03, BACK), (-HALF + 0.04, y + 0.03, WALL_FACE), M["mullion"]))
    right.append(box("sill", (-HALF - 0.1, 0.0, BACK), (-HALF + 0.15, 0.12, WALL_FACE), M["beam"]))
    right.append(box("head", (-HALF - 0.1, CEILING - 0.25, BACK), (-HALF + 0.15, CEILING, WALL_FACE), M["beam"]))
    for a, b in zip(piers, piers[1:]):
        area("dusk", (-HALF - 0.05, 2.0, (a + b) / 2), abs(a - b) - 0.3, 55, DUSK, aim=(0, 1.2, (a + b) / 2), size_y=3.6)
    # A big plant by the glass.
    px, pz = -HALF + 0.7, -1.4
    right.append(cylinder("pot", px, pz, 0.26, 0.0, 0.5, M["terracotta"], segments=20))
    # A fiddle-leaf fig: broad leaves on short stalks up a trunk, each tipped and turned its own way.
    import random
    rl = random.Random(3)
    for k in range(26):
        a = k * 2.399
        y = 0.75 + 0.05 * k
        r = 0.12 + 0.18 * rl.random()
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
        bmesh.ops.scale(bm, vec=(0.15, 0.02, 0.09), verts=bm.verts)
        m = (Matrix.Translation(P(px + r * math.cos(a), y, pz + r * math.sin(a))) @ Matrix.Rotation(-a, 4, 'Z')
             @ Matrix.Rotation(rl.uniform(-0.6, 0.3), 4, 'X') @ Matrix.Translation((0.12, 0, 0)))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        right.append(_mesh_object("leaf", bm, M["green"], smooth=True))
    right.append(rod("stem", (px, 0.5, pz), (px, 2.05, pz), 0.03, M["beam"]))

    # Behind you: a wall of books, oak shelves floor to ceiling, a reading lamp.
    hall.append(back_panel("backwall", BACK - 0.1, 1, [(-HALF, 0.0), (-HALF, CEILING), (HALF, CEILING), (HALF, 0.0)], 0.1, M["plaster"]))
    depth = 0.34
    for xb in [-HALF + 0.2 + 0.95 * i for i in range(10)]:
        hall.append(box("upright", (xb - 0.02, 0.0, BACK), (xb + 0.02, 3.3, BACK + depth), M["oak"]))
    levels = [0.05, 0.45, 0.85, 1.25, 1.65, 2.05, 2.45, 2.85, 3.25]
    for y in levels:
        hall.append(box("shelf", (-HALF + 0.18, y, BACK), (HALF - 0.18, y + 0.03, BACK + depth), M["oak"]))
    import random
    rnd = random.Random(7)
    for li, y in enumerate(levels[:-1]):
        for bay in range(9):
            x0 = -HALF + 0.24 + 0.95 * bay
            x = x0
            while x < x0 + 0.88:
                if rnd.random() < 0.08:
                    x += 0.12; continue
                t = rnd.uniform(0.025, 0.055)
                h = rnd.uniform(0.24, 0.36)
                hall.append(box("book", (x, y + 0.03, BACK + 0.04), (min(x + t, x0 + 0.9), y + 0.03 + h, BACK + depth - 0.02), rnd.choice(M["books"])))
                x += t + 0.002
    # Two lamps: one by the books, one by the glass.
    for (lx, lz) in ((HALF - 1.2, BACK + 0.8), (-HALF + 1.0, -7.6)):
        hall.append(cylinder("lampbase", lx, lz, 0.14, 0.0, 0.03, M["brass"], segments=16))
        hall.append(rod("lampstem", (lx, 0.03, lz), (lx, 1.45, lz), 0.012, M["brass"]))
        glows.append(cylinder("lampshade", lx, lz, 0.2, 1.4, 1.72, M["shade"], segments=20, cap=False))
        point("lamp", (lx, 1.55, lz), 90, LAMP, radius=0.12)
    # Low downlights in the beams' bays, dim.
    for z in (-1.9, -4.0, -6.1, -8.2):
        for x in (-2.4, 2.4):
            glows.append(cylinder("down", x, z, 0.06, CEILING - 0.01, CEILING, M["down"], segments=12))
            spot("down", (x, CEILING - 0.05, z), (x, 0, z), 30, 50, 0.6, (1.0, 0.84, 0.64), radius=0.05)
    # The screen's own soft glow, as from a title waiting.
    area("screenglow", (0, SCREEN_MID, -0.1), SCREEN_W, 70, (0.82, 0.88, 1.0), aim=(0, SCREEN_MID - 1, -6), size_y=SCREEN_H)
    return hall, left, right, glows


def sofa(M):
    """The sofa and what goes with it, round the origin (you), facing +z: a three-seat leather sofa on a wool
    rug, cushions and a throw, a coffee table before you, side tables with a mug and a candle."""
    s = []
    seat_y, back_top = 0.44, 0.82
    s.append(box("rug", (-1.9, 0.0, -1.2), (1.9, 0.015, 1.3), M["rug"], bevel=0.005, segments=1))
    s.append(box("plinth", (-1.15, 0.0, -0.75), (1.15, 0.12, 0.2), M["black"]))
    s.append(box("base", (-1.15, 0.12, -0.75), (1.15, 0.30, 0.25), M["leather"], bevel=0.03, segments=2))
    for i in range(3):
        x0 = -1.0 + i * 0.68
        s.append(box("seat", (x0 + 0.01, 0.30, -0.5), (x0 + 0.67, seat_y, 0.24), M["leather"], bevel=0.05, segments=3))
        s.append(tilt(box("backc", (x0 + 0.01, seat_y - 0.02, -0.72), (x0 + 0.67, back_top, -0.5), M["leather"], bevel=0.06, segments=3), 10, (seat_y, -0.6)))
    for side in (1, -1):
        x0, x1 = sorted((side * 1.0, side * 1.18))
        s.append(box("arm", (x0, 0.12, -0.75), (x1, 0.64, 0.25), M["leather"], bevel=0.06, segments=3))
    s.append(box("cushion", (0.62, seat_y, -0.52), (0.98, seat_y + 0.36, -0.4), M["wool"], bevel=0.06, segments=3))
    s.append(box("cushion", (-0.98, seat_y, -0.52), (-0.6, seat_y + 0.34, -0.4), M["linen"], bevel=0.06, segments=3))
    s.append(box("throw", (0.2, back_top - 0.04, -0.76), (0.7, back_top + 0.01, -0.45), M["wool"], bevel=0.015, segments=2))
    s.append(box("throwfall", (0.2, 0.2, -0.79), (0.7, back_top, -0.76), M["wool"], bevel=0.01, segments=1))
    # The coffee table, low, before you (under every sightline to the screen's foot).
    s.append(box("tabletop", (-0.6, 0.30, 0.55), (0.6, 0.35, 1.05), M["walnut"], bevel=0.015, segments=2))
    for (x, z) in ((-0.52, 0.62), (0.52, 0.62), (-0.52, 0.98), (0.52, 0.98)):
        s.append(box("tableleg", (x - 0.025, 0.0, z - 0.025), (x + 0.025, 0.30, z + 0.025), M["walnut"]))
    s.append(box("tablebook", (-0.35, 0.35, 0.7), (-0.05, 0.38, 0.92), M["books"][1], bevel=0.004, segments=1))
    s.append(box("tablebook2", (-0.33, 0.38, 0.72), (-0.08, 0.41, 0.9), M["books"][4], bevel=0.004, segments=1))
    s.append(cylinder("bowl", 0.25, 0.8, 0.13, 0.35, 0.42, M["ceramic"], segments=20))
    # Side tables with a mug and a candle.
    for side in (1, -1):
        cx = side * 1.5
        s.append(cylinder("sidetop", cx, -0.25, 0.25, 0.52, 0.56, M["walnut"], segments=24))
        s.append(cylinder("sidestem", cx, -0.25, 0.04, 0.0, 0.52, M["brass"], segments=12))
        s.append(cylinder("mug" if side > 0 else "jar", cx - 0.06, -0.3, 0.045, 0.56, 0.66, M["ceramic"], segments=14))
    return s


def main():
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 5
    s.cycles.diffuse_bounces = 4
    s.cycles.glossy_bounces = 0 if mode == "bake" else 1
    s.cycles.sample_clamp_indirect = 4.0
    # The dusk sky's light through the glass: a dim blue world (the glass itself is open).
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.07, 0.14, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.25
    M = materials()
    hall, left, right, glows = room(M)
    sofa_at = -DISTANCES[DEFAULT]
    sofa_objs = sofa(M)
    sofa_obj = join(sofa_objs, "sofa")
    sofa_obj.data.transform(Matrix.Translation(P(0, 0, sofa_at)))
    groups = {"hall": join(hall, "hall"), "walls@L": join(left, "walls@L"), "walls@R": join(right, "walls@R"), "sofa": sofa_obj}
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "1.0"))
    s.view_settings.exposure = math.log2(exposure)

    def view(k, look=None):
        eye = (0.0, EYE, -DISTANCES[k])
        return eye, look or (0, SCREEN_MID - 0.3, 0)

    if mode == "preview":
        for k in (0, 2, 4):
            at, aim = view(k)
            preview(at, aim, os.path.join(out, "size%d.png" % k), res=RES, samples=24 if QUICK else 64, lens=15)
        at, _ = view(2)
        preview(at, (5, 1.2, at[2] + 1.0), os.path.join(out, "left.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        preview(at, (-5, 1.4, at[2] + 1.0), os.path.join(out, "right.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        preview(at, (0, 1.4, -20), os.path.join(out, "back.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return

    eyes = [Vector(P(dx, h, -d + dz)) for d in DISTANCES for dx in (-1.5, 0, 1.5) for h in (1.0, 1.7) for dz in (-0.4, 0.4)]
    occluders = scene_bvh(list(groups.values()) + [glow_obj])
    sizes = {"hall": 4096, "walls@L": 2048, "walls@R": 2048, "sofa": 2048}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {}
    for name, o in groups.items():
        raw[name] = bake(o, sizes[name], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders)
    for name, px in raw.items():
        finish(groups[name], px, out, exposure)
    # The sofa's model is made round you: back to the origin.
    sofa_obj.data.transform(Matrix.Translation(P(0, 0, -sofa_at)))
    export([groups[k] for k in ("hall", "walls@L", "walls@R")] + [glow_obj], os.path.join(out, "cabin.glb"), quality=86)
    export([sofa_obj], os.path.join(out, "cabin_sofa.glb"), quality=86)
    with open(os.path.join(out, "cabin.json"), "w") as f:
        json.dump({"screen": {"width": SCREEN_W, "height": SCREEN_H, "middle": SCREEN_MID, "z": 0.0},
                   "room": {"halfWidth": HALF, "back": BACK, "ceiling": CEILING},
                   "sofa": {"tableFront": 1.05, "tableTop": 0.41}}, f, indent=1)
    sofa_obj.data.transform(Matrix.Translation(P(0, 0, sofa_at)))
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0
    for k in (2,):
        at, aim = view(k)
        preview(at, aim, os.path.join(out, "baked_size%d.png" % k), res=RES, samples=8, lens=15)
        preview(at, (5, 1.2, at[2] + 1.0), os.path.join(out, "baked_left.png"), res=RES, samples=8, lens=15)
        preview(at, (-5, 1.4, at[2] + 1.0), os.path.join(out, "baked_right.png"), res=RES, samples=8, lens=15)
        preview(at, (0, 1.4, -20), os.path.join(out, "baked_back.png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
