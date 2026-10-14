"""Lumiere's lakeside: the end of a timber pontoon on a lake at dusk, modelled and lit, its light baked.

    blender-env/bin/python lakeside.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

Round you, wherever you sit (the screen floats over the water, 14 m out, and
grows with the size): the pontoon's last few metres, weathered planks with
gaps on stringers and posts down into the water; your Adirondack chair and a
second beside it with a blanket over its arm, a crate between with mugs and
a jar candle; a rowing boat tied alongside, oars shipped; iron bollards and
rope; a string of warm bulbs on two poles behind you, lanterns on the back
corners. Nothing stands ahead of your knees: at the largest size the
screen's foot is low over the water and every sightline to it must clear
the boards. The lake and the sky are the sky's picture (Sky on the Quest).

Frame: you at the origin on the deck (y = 0), x to your left, z ahead.
"""
import sys
import os
import math
import json
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from envkit import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402,F401
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402
from cinema import rod  # noqa: E402

AHEAD = 1.15            # the deck's end before you
BEHIND = -9.0           # toward the shore
HALF = 1.6
QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)
WARM = (1.0, 0.68, 0.38)


def materials():
    M = {}
    M["deck"] = textured("deck", (0.36, 0.30, 0.24), (0.22, 0.18, 0.14), "wood", scale=1.6, rough=0.85, bump=0.2)
    M["worn"] = textured("worn", (0.42, 0.37, 0.31), (0.27, 0.23, 0.18), "wood", scale=1.6, rough=0.9, bump=0.2)
    M["post"] = textured("post", (0.20, 0.16, 0.12), (0.10, 0.08, 0.06), "wood", scale=2.0, rough=0.9)
    M["chair"] = textured("chair", (0.62, 0.60, 0.55), (0.50, 0.48, 0.44), "wood", scale=3.0, rough=0.7)
    M["iron"] = material("iron", (0.05, 0.05, 0.05), rough=0.5)
    M["rope"] = textured("rope", (0.55, 0.45, 0.30), (0.40, 0.32, 0.20), "cloth", scale=20, rough=0.9)
    M["blanket"] = textured("blanket", (0.45, 0.12, 0.10), (0.20, 0.25, 0.32), "carpet", scale=6, rough=1)
    M["crate"] = textured("crate", (0.45, 0.33, 0.20), (0.32, 0.22, 0.12), "wood", scale=2.5, rough=0.8)
    M["mug"] = material("mug", (0.70, 0.68, 0.62), rough=0.3)
    M["hull"] = textured("hull", (0.12, 0.26, 0.22), (0.08, 0.18, 0.15), "cloth", scale=2, rough=0.6)
    M["hullin"] = textured("hullin", (0.55, 0.40, 0.24), (0.42, 0.29, 0.16), "wood", scale=2, rough=0.7)
    M["glass"] = material("jarglass", (0.5, 0.45, 0.35), rough=0.2)
    M["bulb"] = glow("bulb", (1.0, 0.78, 0.45))
    M["flame"] = glow("flame", (1.0, 0.70, 0.35))
    M["lanternglass"] = lamp("lantern", (1.0, 0.72, 0.42))
    return M


def adirondack(M, x, z, turn=0.0, blanket=False):
    """An Adirondack chair round (x, z) on the deck, facing +z (turned [turn] degrees toward the middle)."""
    parts = []
    # Seat slats sloping back, a fan of back slats, broad flat arms on front legs.
    for i in range(5):
        sx = -0.27 + i * 0.135
        parts.append(tilt(box("slat", (sx - 0.055, 0.30, -0.40), (sx + 0.055, 0.33, 0.12), M["chair"], bevel=0.008, segments=1), -8, (0.32, 0.12)))
    for i in range(6):
        sx = -0.26 + i * 0.104
        h = 0.95 - abs(i - 2.5) * 0.05
        parts.append(tilt(box("back", (sx - 0.045, 0.28, -0.46), (sx + 0.045, h, -0.43), M["chair"], bevel=0.008, segments=1), 22, (0.30, -0.42)))
    parts.append(tilt(box("backrail", (-0.33, 0.62, -0.49), (0.33, 0.68, -0.44), M["chair"], bevel=0.01, segments=1), 22, (0.30, -0.42)))
    for side in (1, -1):
        ax0, ax1 = sorted((side * 0.30, side * 0.44))
        parts.append(box("arm", (ax0, 0.58, -0.36), (ax1, 0.61, 0.24), M["chair"], bevel=0.01, segments=2))
        lx0, lx1 = sorted((side * 0.33, side * 0.39))
        parts.append(box("frontleg", (lx0, 0.0, 0.10), (lx1, 0.58, 0.17), M["chair"], bevel=0.006, segments=1))
        parts.append(tilt(box("rearleg", (lx0, 0.0, -0.55), (lx1, 0.36, -0.48), M["chair"], bevel=0.006, segments=1), -20, (0.0, -0.5)))
    if blanket:
        parts.append(box("blanket", (0.29, 0.40, -0.30), (0.46, 0.62, 0.10), M["blanket"], bevel=0.03, segments=2))
    o = join(parts, "chair")
    o.data.transform(Matrix.Translation(P(x, 0, z)) @ Matrix.Rotation(math.radians(turn), 4, 'Z'))
    return o


def boat(M, x, z0, z1):
    """A clinker rowing boat lying alongside, low in the water: a lofted hull, thwarts, oars shipped."""
    bm = bmesh.new()
    n, k = 14, 9
    rings = []
    for i in range(n + 1):
        t = i / n
        z = z0 + (z1 - z0) * t
        w = 0.62 * math.sin(math.pi * t) ** 0.6 + 0.02
        d = 0.38 * math.sin(math.pi * t) ** 0.4 + 0.05
        sheer = -0.08 + 0.12 * (2 * t - 1) ** 2
        ring = []
        for j in range(k + 1):
            a = math.pi * j / k
            ring.append(bm.verts.new(P(x + w * math.cos(a), sheer - d * math.sin(a) ** 1.2, z)))
        rings.append(ring)
    for i in range(n):
        for j in range(k):
            bm.faces.new((rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]))
    hull = _mesh_object("hull", bm, M["hull"], smooth=True)
    sol = hull.modifiers.new("t", 'SOLIDIFY'); sol.thickness = 0.03
    parts = [hull]
    for zz in (z0 + 0.9, (z0 + z1) / 2, z1 - 0.8):
        parts.append(box("thwart", (x - 0.5, -0.15, zz - 0.11), (x + 0.5, -0.12, zz + 0.11), M["hullin"], bevel=0.01, segments=1))
    for side in (1, -1):
        parts.append(rod("oar", (x + side * 0.25, -0.05, z0 + 0.5), (x - side * 0.1, -0.02, z1 - 0.3), 0.022, M["hullin"], sides=8))
        parts.append(box("blade", (x - side * 0.1 - 0.07, -0.03, z1 - 0.45), (x - side * 0.1 + 0.07, -0.015, z1 - 0.1), M["hullin"]))
    return parts


def build(M):
    deck, extras, glows = [], [], []
    rnd = random.Random(11)
    # Planks across, 14 cm wide with 1.5 cm gaps; a few more worn; the end plank before your feet.
    z = AHEAD
    while z > BEHIND:
        w = 0.14
        mat = M["worn"] if rnd.random() < 0.25 else M["deck"]
        lift = rnd.uniform(-0.006, 0.004)
        deck.append(box("plank", (-HALF + rnd.uniform(-0.02, 0.02), -0.04 + lift, z - w), (HALF + rnd.uniform(-0.02, 0.02), 0.0 + lift, z), mat, bevel=0.006, segments=1))
        z -= w + 0.015
    for side in (1, -1):
        x0, x1 = sorted((side * (HALF - 0.12), side * HALF))
        deck.append(box("stringer", (x0, -0.26, BEHIND), (x1, -0.04, AHEAD - 0.02), M["post"]))
        deck.append(box("rub", (side * HALF - 0.04 if side > 0 else -HALF - 0.04, -0.2, BEHIND), (side * HALF + 0.04 if side > 0 else -HALF + 0.04, -0.02, AHEAD), M["post"]))
        zz = AHEAD - 0.1
        while zz > BEHIND:
            deck.append(cylinder("pile", side * (HALF - 0.06), zz, 0.11, -1.4, 0.0 if zz < -0.8 else -0.05, M["post"], segments=12))
            zz -= 2.4
    # Bollards and rope beside you, behind your shoulders (never ahead of you).
    for side in (1, -1):
        bx = side * (HALF - 0.2)
        extras.append(cylinder("bollard", bx, -0.9, 0.08, 0.0, 0.26, M["iron"], segments=16))
        extras.append(cylinder("bollardcap", bx, -0.9, 0.11, 0.26, 0.31, M["iron"], segments=16))
    # The rowing boat tied alongside on your right, its painter round the bollard.
    extras += boat(M, -HALF - 0.75, -6.2, -2.0)
    extras.append(rod("painter", (-(HALF - 0.2), 0.2, -0.9), (-HALF - 0.75, -0.05, -2.05), 0.012, M["rope"], sides=6))
    coil_x, coil_z = 1.1, -2.2
    for r in (0.16, 0.13, 0.10):
        y = 0.02 + (0.16 - r) * 0.6
        pts = [(coil_x + r * math.cos(2 * math.pi * i / 16), y, coil_z + r * math.sin(2 * math.pi * i / 16)) for i in range(17)]
        for p0, p1 in zip(pts, pts[1:]):
            extras.append(rod("coil", p0, p1, 0.018, M["rope"], sides=6))
    # Your chair, the second with the blanket, and the crate between with mugs and a jar candle.
    extras.append(adirondack(M, 0.0, 0.0))
    extras.append(adirondack(M, 0.95, -0.15, turn=-12, blanket=True))
    extras.append(box("crate", (0.36, 0.0, -0.05), (0.64, 0.32, 0.25), M["crate"], bevel=0.008, segments=1))
    extras.append(cylinder("mug", 0.42, 0.04, 0.04, 0.32, 0.42, M["mug"], segments=14))
    extras.append(cylinder("mug2", 0.56, 0.16, 0.04, 0.32, 0.42, M["mug"], segments=14))
    extras.append(cylinder("jar", 0.52, 0.0, 0.05, 0.32, 0.45, M["glass"], segments=14))
    glows.append(cylinder("jarflame", 0.52, 0.0, 0.012, 0.36, 0.41, M["flame"], segments=8))
    point("jar", (0.52, 0.42, 0.0), 6, WARM, radius=0.03)
    # Two poles behind you with a string of bulbs between, sagging; lanterns on the back corners.
    poles = [(HALF - 0.1, -3.2), (-(HALF - 0.1), -3.2), (HALF - 0.1, -7.8), (-(HALF - 0.1), -7.8)]
    for (px, pz) in poles:
        extras.append(cylinder("pole", px, pz, 0.05, 0.0, 2.7, M["post"], segments=10))
    for (a, b) in ((poles[0], poles[1]), (poles[0], poles[2]), (poles[1], poles[3])):
        pts = []
        for i in range(13):
            t = i / 12
            x = a[0] + (b[0] - a[0]) * t
            zz = a[1] + (b[1] - a[1]) * t
            y = 2.65 - 0.45 * math.sin(math.pi * t)
            pts.append((x, y, zz))
        for p0, p1 in zip(pts, pts[1:]):
            extras.append(rod("wire", p0, p1, 0.006, M["iron"], sides=4))
        for p in pts[1:-1]:
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.045)
            bmesh.ops.translate(bm, vec=P(p[0], p[1] - 0.08, p[2]), verts=bm.verts)
            glows.append(_mesh_object("bulb", bm, M["bulb"], smooth=True))
            point("bulb", (p[0], p[1] - 0.1, p[2]), 9, (1.0, 0.72, 0.42), radius=0.04)
    for side in (1, -1):
        lx, lz = side * (HALF - 0.25), -2.6
        extras.append(box("lanternbase", (lx - 0.1, 0.0, lz - 0.1), (lx + 0.1, 0.04, lz + 0.1), M["iron"]))
        glows.append(box("lanternglass", (lx - 0.08, 0.04, lz - 0.08), (lx + 0.08, 0.30, lz + 0.08), M["lanternglass"]))
        extras.append(box("lanterntop", (lx - 0.11, 0.30, lz - 0.11), (lx + 0.11, 0.36, lz + 0.11), M["iron"], bevel=0.01, segments=1))
        point("lantern", (lx, 0.2, lz), 25, WARM, radius=0.06)
    return deck, extras, glows


def main():
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 4
    s.cycles.diffuse_bounces = 3
    s.cycles.sample_clamp_indirect = 4.0
    # Dusk: a deep blue sky all round, a warm glow low ahead where the sun has gone.
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.13, 0.26, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    sun = bpy.data.lights.new("afterglow", 'SUN'); sun.energy = 0.6; sun.color = (1.0, 0.55, 0.35); sun.angle = math.radians(12)
    so = bpy.data.objects.new("afterglow", sun); bpy.context.collection.objects.link(so)
    from mathutils import Vector as V
    so.rotation_mode = 'QUATERNION'; so.rotation_quaternion = (V(P(0, 0, 0)) - V(P(0.3, 0.12, 1))).to_track_quat('-Z', 'Y')
    M = materials()
    deck, extras, glows = build(M)
    groups = {"pontoon": join(deck, "pontoon"), "things": join(extras, "things")}
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "1.3"))
    s.view_settings.exposure = math.log2(exposure)
    eye = (0.0, 1.15, 0.0)
    views = {"ahead": (0, 0.9, 10), "left": (5, 0.6, 1), "right": (-5, 0.4, 0), "back": (0, 0.8, -10), "down": (0.4, 0, 1.2)}
    if mode == "preview":
        for k, aim in views.items():
            preview(eye, aim, os.path.join(out, k + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return
    eyes = [Vector(P(dx, h, dz)) for dx in (-1.0, 0, 1.0) for h in (1.0, 1.7) for dz in (-0.5, 0, 0.5)]
    occluders = scene_bvh(list(groups.values()) + [glow_obj])
    sizes = {"pontoon": 4096, "things": 4096}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {n: bake(o, sizes[n], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders) for n, o in groups.items()}
    for n, px in raw.items():
        finish(groups[n], px, out, exposure)
    export(list(groups.values()) + [glow_obj], os.path.join(out, "lakeside.glb"), quality=86)
    with open(os.path.join(out, "lakeside.json"), "w") as f:
        json.dump({"deckAhead": AHEAD, "halfWidth": HALF}, f, indent=1)
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    for k in ("left", "back", "down"):
        preview(eye, views[k], os.path.join(out, "baked_" + k + ".png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
