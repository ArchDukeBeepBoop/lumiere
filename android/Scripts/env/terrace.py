"""Lumiere's terrace above the clouds: a teak deck at golden hour, modelled and lit, its light baked.

    blender-env/bin/python terrace.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

Round you, wherever you sit (the screen hangs in the air 16 m out, growing
with the size): a teak deck afloat on the cloud sea (the sky's picture),
its boards running out a metre before you and stopping there, open to the
clouds — every sightline to the screen's foot clears it. Beside and behind
you: steel posts with taut cable rails, your deep lounge chair and a lounger
beside it, a low table with two glasses and a carafe, olive trees in tall
planters, lanterns on the deck, a fire bowl glowing behind you, and a
canvas sail overhead. Lit by a low warm sun from ahead and the sky's blue.

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

AHEAD, BEHIND, HALF = 1.2, -6.5, 2.4
QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)


def materials():
    M = {}
    M["teak"] = textured("teak", (0.48, 0.30, 0.16), (0.34, 0.20, 0.10), "wood", scale=1.5, rough=0.6)
    M["steel"] = material("steel", (0.30, 0.30, 0.31), rough=0.35)
    M["cushion"] = textured("cushion", (0.78, 0.74, 0.66), (0.68, 0.64, 0.56), "cloth", scale=8, rough=0.9)
    M["frame"] = material("frame", (0.06, 0.06, 0.065), rough=0.5)
    M["planter"] = textured("planter", (0.45, 0.43, 0.40), (0.36, 0.34, 0.31), "carpet", scale=4, rough=0.9)
    M["soil"] = material("soil", (0.06, 0.04, 0.03), rough=1)
    M["olive"] = textured("olive", (0.22, 0.27, 0.14), (0.14, 0.18, 0.09), "cloth", scale=10, rough=0.8)
    M["bark"] = textured("bark", (0.25, 0.21, 0.17), (0.15, 0.12, 0.09), "wood", scale=5, rough=0.9)
    M["glass"] = material("glass", (0.55, 0.62, 0.62), rough=0.1)
    M["wine"] = material("wine", (0.35, 0.05, 0.07), rough=0.2)
    M["sail"] = textured("sail", (0.90, 0.87, 0.80), (0.82, 0.78, 0.70), "cloth", scale=6, rough=0.9)
    M["throw"] = textured("throwt", (0.20, 0.30, 0.42), (0.14, 0.22, 0.32), "carpet", scale=6, rough=1)
    M["fire"] = glow("firebowl", (1.0, 0.55, 0.2))
    M["lantern"] = lamp("lantern", (1.0, 0.76, 0.45))
    return M


def lounge_chair(M, x, z, turn=0.0):
    p = []
    p.append(box("frame", (-0.42, 0.05, -0.45), (0.42, 0.30, 0.38), M["frame"], bevel=0.02, segments=2))
    for side in (1, -1):
        x0, x1 = sorted((side * 0.36, side * 0.46))
        p.append(box("arm", (x0, 0.05, -0.45), (x1, 0.62, 0.38), M["frame"], bevel=0.02, segments=2))
    p.append(box("seat", (-0.36, 0.30, -0.42), (0.36, 0.44, 0.36), M["cushion"], bevel=0.05, segments=3))
    p.append(tilt(box("back", (-0.36, 0.40, -0.45), (0.36, 0.95, -0.28), M["cushion"], bevel=0.06, segments=3), 12, (0.42, -0.4)))
    p.append(box("pillow", (-0.22, 0.42, -0.30), (0.12, 0.74, -0.16), M["throw"], bevel=0.06, segments=3))
    for (lx, lz) in ((-0.4, -0.42), (0.4, -0.42), (-0.4, 0.34), (0.4, 0.34)):
        p.append(cylinder("foot", lx, lz, 0.025, 0.0, 0.05, M["steel"], segments=8))
    o = join(p, "lounge")
    o.data.transform(Matrix.Translation(P(x, 0, z)) @ Matrix.Rotation(math.radians(turn), 4, 'Z'))
    return o


def lounger(M, x, z):
    p = [box("lframe", (x - 0.35, 0.10, z - 1.0), (x + 0.35, 0.28, z + 0.95), M["teak"], bevel=0.02, segments=2),
         box("lpad", (x - 0.32, 0.28, z - 0.95), (x + 0.32, 0.36, z + 0.9), M["cushion"], bevel=0.035, segments=2)]
    p.append(tilt(box("lback", (x - 0.32, 0.30, z - 1.0), (x + 0.32, 0.38, z - 0.35), M["cushion"], bevel=0.035, segments=2), -40, (0.34, z - 0.35)))
    for (lx, lz) in ((x - 0.3, z - 0.9), (x + 0.3, z - 0.9), (x - 0.3, z + 0.85), (x + 0.3, z + 0.85)):
        p.append(box("lleg", (lx - 0.03, 0.0, lz - 0.03), (lx + 0.03, 0.10, lz + 0.03), M["teak"]))
    p.append(box("towel", (x - 0.28, 0.36, z + 0.3), (x + 0.28, 0.38, z + 0.75), M["throw"], bevel=0.01, segments=1))
    return p


def olive_tree(M, x, z, seed):
    r = random.Random(seed)
    p = [box("planter", (x - 0.4, 0.0, z - 0.4), (x + 0.4, 0.8, z + 0.4), M["planter"], bevel=0.02, segments=2),
         box("soil", (x - 0.36, 0.76, z - 0.36), (x + 0.36, 0.78, z + 0.36), M["soil"])]
    p.append(rod("trunk", (x, 0.78, z), (x + 0.08, 1.7, z - 0.05), 0.06, M["bark"], sides=8))
    for k in range(90):
        a = r.uniform(0, 2 * math.pi); rr = r.uniform(0.05, 0.7) * r.uniform(0.6, 1.0); y = r.uniform(1.55, 2.55)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r.uniform(0.07, 0.14))
        bmesh.ops.scale(bm, vec=(1.0, 1.0, 0.7), verts=bm.verts)
        bmesh.ops.translate(bm, vec=P(x + rr * math.cos(a), y, z + rr * math.sin(a)), verts=bm.verts)
        p.append(_mesh_object("foliage", bm, M["olive"], smooth=True))
    return p


def build(M):
    deck, things, glows = [], [], []
    z = AHEAD
    while z > BEHIND:
        deck.append(box("board", (-HALF, -0.05, z - 0.12), (HALF, 0.0, z), M["teak"], bevel=0.004, segments=1))
        z -= 0.13
    deck.append(box("fascia", (-HALF - 0.03, -0.35, BEHIND), (HALF + 0.03, -0.05, AHEAD), M["frame"]))
    # Rails along the sides and across behind: steel posts with four taut cables.
    for side in (1, -1):
        zz = AHEAD - 0.2
        posts = []
        while zz > BEHIND:
            posts.append(zz); zz -= 1.6
        posts.append(BEHIND + 0.05)
        for pz in posts:
            things.append(box("post", (side * HALF - 0.03, 0.0, pz - 0.03), (side * HALF + 0.03, 1.05, pz + 0.03), M["steel"]))
        for y in (0.25, 0.5, 0.75, 1.0):
            things.append(rod("cable", (side * HALF, y, posts[0]), (side * HALF, y, posts[-1]), 0.004 if y < 1.0 else 0.02, M["steel"], sides=6))
    for y in (0.25, 0.5, 0.75, 1.0):
        things.append(rod("cableback", (HALF, y, BEHIND + 0.05), (-HALF, y, BEHIND + 0.05), 0.004 if y < 1.0 else 0.02, M["steel"], sides=6))
    # Your chair, the lounger on your left, the table between with two glasses and a carafe.
    things.append(lounge_chair(M, 0.0, 0.0))
    things += lounger(M, 1.45, -0.6)
    things.append(cylinder("tabletop", 0.78, -0.1, 0.28, 0.36, 0.40, M["teak"], segments=28))
    things.append(cylinder("tablebase", 0.78, -0.1, 0.06, 0.0, 0.36, M["steel"], segments=12))
    for (gx, gz) in ((0.70, -0.02), (0.86, -0.18)):
        things.append(cylinder("glass", gx, gz, 0.035, 0.40, 0.55, M["glass"], segments=14))
        things.append(cylinder("winein", gx, gz, 0.031, 0.42, 0.47, M["wine"], segments=14))
    things.append(cylinder("carafe", 0.74, -0.25, 0.06, 0.40, 0.62, M["glass"], segments=16))
    # Olive trees behind, a fire bowl behind you on the left, lanterns about.
    things += olive_tree(M, HALF - 0.55, -3.6, 1)
    things += olive_tree(M, -HALF + 0.55, -3.0, 2)
    things += olive_tree(M, -HALF + 0.55, -5.6, 3)
    fx, fz = 1.0, -3.2
    things.append(cylinder("bowl", fx, fz, 0.45, 0.25, 0.45, M["frame"], segments=28))
    things.append(cylinder("bowlstand", fx, fz, 0.18, 0.0, 0.25, M["frame"], segments=16))
    glows.append(cylinder("fire", fx, fz, 0.38, 0.45, 0.47, M["fire"], segments=24))
    point("firebowl", (fx, 0.75, fz), 120, (1.0, 0.55, 0.22), radius=0.3)
    for (lx, lz) in ((-HALF + 0.3, 0.6), (-HALF + 0.3, -1.6), (HALF - 0.3, -1.2)):
        things.append(box("lanternbase", (lx - 0.12, 0.0, lz - 0.12), (lx + 0.12, 0.05, lz + 0.12), M["frame"]))
        glows.append(box("lanternglass", (lx - 0.10, 0.05, lz - 0.10), (lx + 0.10, 0.42, lz + 0.10), M["lantern"]))
        things.append(box("lanterntop", (lx - 0.13, 0.42, lz - 0.13), (lx + 0.13, 0.48, lz + 0.13), M["frame"], bevel=0.01, segments=1))
        point("lantern", (lx, 0.28, lz), 18, (1.0, 0.7, 0.4), radius=0.08)
    # A canvas sail overhead behind you, on two masts.
    for (mx, mz) in ((HALF - 0.1, -1.8), (-HALF + 0.1, -5.8)):
        things.append(cylinder("mast", mx, mz, 0.05, 0.0, 3.2, M["steel"], segments=10))
    bm = bmesh.new()
    corners = [P(HALF - 0.1, 3.1, -1.8), P(-HALF + 0.1, 2.5, -1.4), P(-HALF + 0.1, 3.1, -5.8), P(HALF - 0.1, 2.5, -6.2)]
    vs = [bm.verts.new(c) for c in corners]
    bm.faces.new(vs)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)
    for v in bm.verts:
        c = Vector(sum((Vector(x) for x in corners), Vector()) / 4)
        d = (v.co - c).length
        v.co.z -= 0.25 * max(0, 1 - d / 3)
    sail = _mesh_object("sail", bm, M["sail"], smooth=True)
    sail.modifiers.new("t", 'SOLIDIFY').thickness = 0.01
    things.append(sail)
    return deck, things, glows


def main():
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 4
    s.cycles.diffuse_bounces = 3
    s.cycles.sample_clamp_indirect = 4.0
    # Golden hour above the clouds: a pale blue sky, a low warm sun ahead and to the left, the clouds' bright floor.
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.58, 0.85, 1)
    s.world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sun = bpy.data.lights.new("sun", 'SUN'); sun.energy = 3.2; sun.color = (1.0, 0.78, 0.55); sun.angle = math.radians(2)
    so = bpy.data.objects.new("sun", sun); bpy.context.collection.objects.link(so)
    so.rotation_mode = 'QUATERNION'; so.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(0.6, 0.25, 1))).to_track_quat('-Z', 'Y')
    bounce = bpy.data.lights.new("cloudfloor", 'SUN'); bounce.energy = 0.6; bounce.color = (1.0, 0.92, 0.85)
    bo = bpy.data.objects.new("cloudfloor", bounce); bpy.context.collection.objects.link(bo)
    bo.rotation_mode = 'QUATERNION'; bo.rotation_quaternion = (Vector(P(0, 1, 0)) - Vector(P(0, 0, 0))).to_track_quat('-Z', 'Y')
    M = materials()
    deck, things, glows = build(M)
    groups = {"deck": join(deck, "deck"), "things": join(things, "things")}
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "0.9"))
    s.view_settings.exposure = math.log2(exposure)
    eye = (0.0, 1.15, 0.0)
    views = {"ahead": (0, 0.9, 10), "left": (5, 0.6, 0), "right": (-5, 0.6, 0), "back": (0, 0.9, -10)}
    if mode == "preview":
        for k, aim in views.items():
            preview(eye, aim, os.path.join(out, k + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return
    eyes = [Vector(P(dx, h, dz)) for dx in (-1.0, 0, 1.0) for h in (1.0, 1.7) for dz in (-0.5, 0, 0.5)]
    occluders = scene_bvh(list(groups.values()) + [glow_obj])
    sizes = {"deck": 2048, "things": 4096}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {n: bake(o, sizes[n], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders) for n, o in groups.items()}
    for n, px in raw.items():
        finish(groups[n], px, out, exposure)
    export(list(groups.values()) + [glow_obj], os.path.join(out, "terrace.glb"), quality=86)
    with open(os.path.join(out, "terrace.json"), "w") as f:
        json.dump({"deckAhead": AHEAD, "halfWidth": HALF}, f, indent=1)
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    for k in ("left", "back"):
        preview(eye, views[k], os.path.join(out, "baked_" + k + ".png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
