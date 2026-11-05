"""Lumiere's Moon base: an observation deck on the lunar surface, modelled and lit, its light baked.

    blender-env/bin/python moonbase.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

Round you, wherever you sit (the screen stands out on the surface 18 m away,
growing with the size): a steel deck on legs over the regolith (the sky's
picture), diamond tread-plate with a hazard-striped front edge a metre before
you, open there so every sightline to the screen's foot clears it. Beside
and behind you: your crew seat, safety rails, equipment cases, a rack of
oxygen bottles, a toolbox, two work lights on poles, a comms mast with its
dish and a red beacon, a pressurised habitat's hatch behind you with lit
ports. Lit as the Moon is: one hard white sun low from the left, no air to
soften it, a faint blue earthshine.

Frame: you at the origin on the deck (y = 0), x to your left, z ahead.
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
from cinema import rod  # noqa: E402

AHEAD, BEHIND, HALF = 1.1, -6.0, 2.6
QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)


def materials():
    M = {}
    M["plate"] = textured("treadplate", (0.42, 0.42, 0.43), (0.30, 0.30, 0.31), "carpet", scale=14, rough=0.4, bump=0.4)
    M["steel"] = material("steel", (0.35, 0.35, 0.36), rough=0.4)
    M["dark"] = material("darksteel", (0.06, 0.06, 0.065), rough=0.5)
    M["yellow"] = material("hazardy", (0.75, 0.55, 0.05), rough=0.5)
    M["black"] = material("hazardk", (0.02, 0.02, 0.02), rough=0.5)
    M["case"] = textured("case", (0.55, 0.50, 0.42), (0.45, 0.40, 0.33), "cloth", scale=4, rough=0.6)
    M["orange"] = material("orange", (0.75, 0.25, 0.04), rough=0.5)
    M["white"] = textured("hullwhite", (0.78, 0.78, 0.76), (0.68, 0.68, 0.66), "cloth", scale=3, rough=0.5)
    M["green"] = material("bottlegreen", (0.10, 0.30, 0.15), rough=0.4)
    M["seat"] = textured("seatfabric", (0.12, 0.14, 0.18), (0.08, 0.09, 0.12), "cloth", scale=8, rough=0.8)
    M["gold"] = material("foil", (0.60, 0.45, 0.12), rough=0.3)
    M["beacon"] = glow("beacon", (1.0, 0.1, 0.05))
    M["worklight"] = lamp("worklight", (1.0, 0.97, 0.9))
    M["port"] = lamp("port", (0.7, 0.85, 1.0))
    M["status"] = glow("status", (0.2, 1.0, 0.5))
    return M


def build(M):
    deck, things, glows = [], [], []
    # The deck: tread-plate panels on a frame, legs down to the surface, the front edge striped.
    x = -HALF
    while x < HALF - 0.01:
        z = AHEAD
        while z > BEHIND + 0.01:
            deck.append(box("plate", (x + 0.004, -0.03, z - 1.2 + 0.004), (min(x + 1.3, HALF) - 0.004, 0.0, z - 0.004), M["plate"], bevel=0.003, segments=1))
            z -= 1.2
        x += 1.3
    deck.append(box("frame", (-HALF - 0.05, -0.25, BEHIND), (HALF + 0.05, -0.03, AHEAD), M["dark"]))
    for i in range(14):
        x0 = -HALF + i * (2 * HALF / 14)
        deck.append(box("stripe", (x0, -0.001, AHEAD - 0.12), (x0 + HALF / 14, 0.002, AHEAD), M["yellow"] if i % 2 == 0 else M["black"]))
    for (lx, lz) in ((HALF - 0.2, AHEAD - 0.3), (-HALF + 0.2, AHEAD - 0.3), (HALF - 0.2, BEHIND + 0.3), (-HALF + 0.2, BEHIND + 0.3), (HALF - 0.2, -2.4), (-HALF + 0.2, -2.4)):
        deck.append(rod("leg", (lx, -0.25, lz), (lx * 1.08, -2.2, lz), 0.07, M["steel"], sides=10))
        deck.append(cylinder("foot", lx * 1.08, lz, 0.25, -2.25, -2.18, M["dark"], segments=16))
    # Rails: along the sides and behind (none across the front).
    for side in (1, -1):
        posts = [AHEAD - 0.4, -1.4, -3.2, BEHIND + 0.1]
        for pz in posts:
            things.append(box("railpost", (side * HALF - 0.03, 0.0, pz - 0.03), (side * HALF + 0.03, 1.05, pz + 0.03), M["yellow"]))
        for y in (0.5, 1.02):
            things.append(rod("rail", (side * HALF, y, posts[0]), (side * HALF, y, posts[-1]), 0.025, M["yellow"], sides=8))
    # Your crew seat, a padded shell on a pedestal.
    things.append(cylinder("pedestal", 0, -0.05, 0.08, 0.0, 0.32, M["steel"], segments=14))
    things.append(box("seatpan", (-0.30, 0.32, -0.38), (0.30, 0.46, 0.25), M["seat"], bevel=0.04, segments=2))
    things.append(tilt(box("seatback", (-0.30, 0.42, -0.42), (0.30, 1.0, -0.28), M["seat"], bevel=0.05, segments=2), 14, (0.44, -0.36)))
    for side in (1, -1):
        x0, x1 = sorted((side * 0.30, side * 0.37))
        things.append(box("seatarm", (x0, 0.46, -0.36), (x1, 0.62, 0.15), M["dark"], bevel=0.02, segments=2))
    # Equipment: cases, an oxygen rack, a toolbox, by your sides and behind.
    for (cx, cz, w, h, d, mat) in ((1.9, -0.6, 0.7, 0.45, 0.5, "case"), (1.9, -1.3, 0.6, 0.35, 0.45, "orange"), (-1.9, -1.0, 0.8, 0.5, 0.55, "case"),
                                   (-1.95, -1.8, 0.5, 0.3, 0.4, "white")):
        things.append(box("case", (cx - w / 2, 0.0, cz - d / 2), (cx + w / 2, h, cz + d / 2), M[mat], bevel=0.025, segments=2))
        things.append(box("caselatch", (cx - 0.05, h * 0.6, cz + d / 2), (cx + 0.05, h * 0.75, cz + d / 2 + 0.015), M["dark"]))
    rx, rz = -1.7, -3.6
    things.append(box("rackframe", (rx - 0.5, 0.0, rz - 0.25), (rx + 0.5, 0.06, rz + 0.25), M["dark"]))
    things.append(box("rackbar", (rx - 0.5, 1.0, rz - 0.04), (rx + 0.5, 1.06, rz + 0.04), M["dark"]))
    for i in range(5):
        bx = rx - 0.4 + i * 0.2
        things.append(cylinder("bottle", bx, rz, 0.085, 0.06, 1.15, M["green"], segments=16))
        things.append(cylinder("valve", bx, rz, 0.03, 1.15, 1.25, M["steel"], segments=8))
    things.append(box("toolbox", (1.5, 0.0, -2.6), (2.1, 0.32, -2.25), M["orange"], bevel=0.02, segments=2))
    things.append(rod("handle", (1.6, 0.36, -2.42), (2.0, 0.36, -2.42), 0.015, M["dark"], sides=6))
    # Work lights on poles behind you, aimed at the deck.
    for side in (1, -1):
        px, pz = side * (HALF - 0.3), -3.0
        things.append(cylinder("lightpole", px, pz, 0.04, 0.0, 2.6, M["steel"], segments=10))
        things.append(box("lamphead", (px - 0.18, 2.55, pz - 0.08), (px + 0.18, 2.75, pz + 0.12), M["dark"], bevel=0.02, segments=1))
        glows.append(box("lampface", (px - 0.15, 2.57, pz + 0.12), (px + 0.15, 2.73, pz + 0.125), M["worklight"]))
        spot("work", (px, 2.6, pz + 0.2), (0, 0, 0.0), 260, 70, 0.5, (1.0, 0.97, 0.92), radius=0.1)
    # The comms mast with its dish and beacon, behind on the right.
    mx, mz = -2.0, -5.2
    things.append(cylinder("mast", mx, mz, 0.06, 0.0, 4.0, M["steel"], segments=12))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=32, radius1=0.65, radius2=0.05, depth=0.3)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(P(mx + 0.3, 3.2, mz + 0.3)) @ Matrix.Rotation(math.radians(60), 4, 'X'), verts=bm.verts)
    dish = _mesh_object("dish", bm, M["white"], smooth=True)
    dish.modifiers.new("t", 'SOLIDIFY').thickness = 0.02
    things.append(dish)
    glows.append(cylinder("beacon", mx, mz, 0.07, 4.0, 4.14, M["beacon"], segments=12))
    # The habitat behind you: a curved hull wall with a hatch and lit ports.
    hz = BEHIND - 0.6
    bm = bmesh.new()
    segs, ring = 24, []
    for i in range(segs + 1):
        a = math.pi * i / segs
        ring.append((3.6 * math.cos(a), 3.2 * math.sin(a)))
    top = [bm.verts.new(P(x, y, hz)) for x, y in ring]
    bot = [bm.verts.new(P(x, y, hz - 4)) for x, y in ring]
    for i in range(segs):
        bm.faces.new((top[i], top[i + 1], bot[i + 1], bot[i]))
    hull = _mesh_object("habitat", bm, M["white"], smooth=True)
    hull.modifiers.new("t", 'SOLIDIFY').thickness = 0.05
    things.append(hull)
    things.append(back_panel("hullend", hz, 1, [(x, y) for x, y in ring] + [(-3.6, 0.0)], 0.04, M["white"]))
    things.append(box("hatch", (-0.55, 0.05, hz + 0.04), (0.55, 2.0, hz + 0.12), M["dark"], bevel=0.05, segments=2))
    things.append(box("hatchring", (-0.65, 0.0, hz + 0.02), (0.65, 2.1, hz + 0.06), M["steel"], bevel=0.04, segments=2))
    for px in (-2.2, 2.2):
        glows.append(cylinder("port", px, hz + 0.06, 0.25, 1.6, 1.6, M["port"], segments=20))
        glows.append(box("portface", (px - 0.22, 1.38, hz + 0.05), (px + 0.22, 1.82, hz + 0.07), M["port"]))
        point("port", (px, 1.6, hz + 0.4), 20, (0.7, 0.85, 1.0), radius=0.2)
    for i in range(4):
        glows.append(box("status", (0.75, 1.5 - i * 0.12, hz + 0.05), (0.85, 1.56 - i * 0.12, hz + 0.07), M["status"]))
    things.append(box("foilpatch", (1.2, 0.2, hz + 0.04), (2.6, 1.0, hz + 0.06), M["gold"]))
    return deck, things, glows


def main():
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 3
    s.cycles.diffuse_bounces = 2
    s.cycles.sample_clamp_indirect = 4.0
    # No air: a black sky, one hard sun low from the left, faint blue earthshine from above ahead, the grey ground's bounce.
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.0, 0.0, 0.0, 1)
    sun = bpy.data.lights.new("sun", 'SUN'); sun.energy = 4.5; sun.color = (1.0, 0.98, 0.95); sun.angle = math.radians(0.5)
    so = bpy.data.objects.new("sun", sun); bpy.context.collection.objects.link(so)
    so.rotation_mode = 'QUATERNION'; so.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(1.0, 0.35, 0.3))).to_track_quat('-Z', 'Y')
    earth = bpy.data.lights.new("earthshine", 'SUN'); earth.energy = 0.15; earth.color = (0.6, 0.75, 1.0); earth.angle = math.radians(2)
    eo = bpy.data.objects.new("earthshine", earth); bpy.context.collection.objects.link(eo)
    eo.rotation_mode = 'QUATERNION'; eo.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(-0.2, 0.6, 1))).to_track_quat('-Z', 'Y')
    ground = bpy.data.lights.new("regolith", 'SUN'); ground.energy = 0.5; ground.color = (0.9, 0.88, 0.85)
    go = bpy.data.objects.new("regolith", ground); bpy.context.collection.objects.link(go)
    go.rotation_mode = 'QUATERNION'; go.rotation_quaternion = (Vector(P(0, 1, 0)) - Vector(P(0, 0, 0))).to_track_quat('-Z', 'Y')
    M = materials()
    deck, things, glows = build(M)
    groups = {"deck": join(deck, "deck"), "things": join(things, "things")}
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "1.0"))
    s.view_settings.exposure = math.log2(exposure)
    eye = (0.0, 1.15, 0.0)
    views = {"ahead": (0, 0.9, 10), "left": (5, 0.6, 0), "right": (-5, 0.6, 0), "back": (0, 1.2, -10)}
    if mode == "preview":
        for k, aim in views.items():
            preview(eye, aim, os.path.join(out, k + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return
    eyes = [Vector(P(dx, h, dz)) for dx in (-1.0, 0, 1.0) for h in (1.0, 1.7) for dz in (-0.5, 0, 0.5)]
    occluders = scene_bvh(list(groups.values()) + [glow_obj])
    sizes = {"deck": 2048, "things": 4096}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {n: bake(o, sizes[n], samples=16 if QUICK else 64, eyes=eyes, scene_bvh=occluders) for n, o in groups.items()}
    for n, px in raw.items():
        finish(groups[n], px, out, exposure)
    export(list(groups.values()) + [glow_obj], os.path.join(out, "moonbase.glb"), quality=86)
    with open(os.path.join(out, "moonbase.json"), "w") as f:
        json.dump({"deckAhead": AHEAD, "halfWidth": HALF}, f, indent=1)
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    for k in ("left", "back"):
        preview(eye, views[k], os.path.join(out, "baked_" + k + ".png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
