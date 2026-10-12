"""Lumiere's space station: an observation module in low orbit, modelled and lit, its light baked.

    blender-env/bin/python station.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

Built round its screen, 4 m across on the forward bulkhead (StationRoom on
the Quest); the sizes are how near you float. A module with a rounded
section: white hull panels with seams and fasteners between dark frames,
big windows down both sides and a skylight over you, the Earth below and the
stars beyond (the sky's picture); handrails along the walls, LED strips and
status lights, lockers, the hatch behind you with a photo taped by it, a
grow box of greens on your left, a laptop on its arm on your right, cable
runs, and a notebook, a pen and a water pouch drifting free.

Frame: the origin on the deck under the screen's middle, the screen's face at
z = 0, x to your left, z toward the screen.
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

SCREEN_W = 4.0
SCREEN_H = SCREEN_W * 9 / 16
SCREEN_MID = 1.5
DEGREES = [55, 70, 85, 100, 115]
DISTANCES = [SCREEN_W / (2 * math.tan(math.radians(d / 2))) for d in DEGREES]
BACK = -6.4
HALF = 2.3
HEIGHT = 3.0
QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)
EYE = 1.2


def materials():
    M = {}
    M["hull"] = textured("panel", (0.80, 0.80, 0.79), (0.72, 0.72, 0.71), "cloth", scale=3, rough=0.5)
    M["frame"] = material("frame", (0.07, 0.075, 0.08), rough=0.4)
    M["deck"] = textured("decking", (0.30, 0.31, 0.33), (0.22, 0.23, 0.25), "carpet", scale=10, rough=0.6)
    M["rail"] = material("rail", (0.55, 0.56, 0.58), rough=0.3)
    M["locker"] = textured("locker", (0.62, 0.63, 0.64), (0.55, 0.56, 0.57), "cloth", scale=4, rough=0.5)
    M["blue"] = material("velcro", (0.10, 0.18, 0.35), rough=0.8)
    M["cable"] = material("cable", (0.08, 0.08, 0.09), rough=0.6)
    M["green"] = textured("greens", (0.12, 0.35, 0.10), (0.06, 0.22, 0.05), "cloth", scale=12, rough=0.8)
    M["laptop"] = material("laptop", (0.15, 0.15, 0.16), rough=0.3)
    M["paper"] = material("paper", (0.85, 0.84, 0.80), rough=0.9)
    M["pouch"] = material("pouch", (0.55, 0.60, 0.70), rough=0.3)
    M["photo"] = textured("photo", (0.55, 0.45, 0.35), (0.25, 0.35, 0.50), "carpet", scale=20, rough=0.4)
    M["screen"] = lamp("screen", (0.05, 0.05, 0.055))
    M["led"] = lamp("led", (0.85, 0.92, 1.0))
    M["status"] = glow("statusg", (0.2, 1.0, 0.5))
    M["statusr"] = glow("statusr", (1.0, 0.25, 0.1))
    M["growlight"] = glow("grow", (0.85, 0.4, 1.0))
    M["laptopscreen"] = glow("laptopscreen", (0.45, 0.6, 0.9))
    return M


def section(t):
    """The module's cross-section, round from the deck's left edge up over and down to its right: (x, y) at t 0..1."""
    # A rounded rectangle: straight walls, a curved crown, the deck flat between.
    pts = [(HALF, 0.0), (HALF, 1.9)]
    for i in range(1, 12):
        a = math.pi * i / 12
        pts.append((HALF * math.cos(a), 1.9 + (HEIGHT - 1.9) * math.sin(a)))
    pts += [(-HALF, 1.9), (-HALF, 0.0)]
    return pts


def build(M):
    hull, things, glows = [], [], []
    # Ribs (dark frames) every 1.1 m along the module; white panels between them, with windows on the sides.
    ribs = [0.08 - 1.1 * i for i in range(7)]
    ring = section(0)
    for z in ribs:
        for (x0, y0), (x1, y1) in zip(ring, ring[1:]):
            hull.append(rod("rib", (x0 * 0.98, y0, z), (x1 * 0.98, y1, z), 0.05, M["frame"], sides=6))
    windows = {1: (0.55, 1.75), 2: (0.55, 1.75), 4: (0.55, 1.75)}   # between ribs i and i+1: window from y to y
    for i, (za, zb) in enumerate(zip(ribs, ribs[1:])):
        for (x0, y0), (x1, y1) in zip(ring, ring[1:]):
            side_wall = abs(x0 - x1) < 1e-3 and abs(abs(x0) - HALF) < 1e-3
            crown_mid = y0 > HEIGHT - 0.2 and y1 > HEIGHT - 0.2
            if side_wall and i in windows:
                lo, hi = windows[i]
                # The wall round the window: below it and above it.
                for (ya, yb) in ((y0, lo), (hi, y1)) if y0 < y1 else ((y1, lo), (hi, y0)):
                    if yb - ya > 0.01:
                        hull.append(panel("wallpanel", x0 + (0.05 if x0 > 0 else -0.05), -1 if x0 > 0 else 1,
                                          [(za - 0.06, ya), (za - 0.06, yb), (zb + 0.06, yb), (zb + 0.06, ya)], 0.05, M["hull"], bevel=0.01, segments=1))
                hull.append(panel("windowframe", x0, -1 if x0 > 0 else 1, [(za - 0.06, lo - 0.08), (za - 0.06, lo), (zb + 0.06, lo), (zb + 0.06, lo - 0.08)], 0.1, M["frame"]))
                hull.append(panel("windowframe", x0, -1 if x0 > 0 else 1, [(za - 0.06, hi), (za - 0.06, hi + 0.08), (zb + 0.06, hi + 0.08), (zb + 0.06, hi)], 0.1, M["frame"]))
                continue
            if crown_mid and i == 3:
                continue    # the skylight over you
            bm = bmesh.new()
            vs = [bm.verts.new(P(x0, y0, za - 0.05)), bm.verts.new(P(x1, y1, za - 0.05)), bm.verts.new(P(x1, y1, zb + 0.05)), bm.verts.new(P(x0, y0, zb + 0.05))]
            bm.faces.new(vs)
            o = _mesh_object("panel", bm, M["hull"])
            o.modifiers.new("t", 'SOLIDIFY').thickness = 0.04
            hull.append(o)
    # The deck: grey plates, a recessed rail of tie-down points down the middle.
    hull.append(box("deck", (-HALF, -0.05, BACK), (HALF, 0.0, 0.1), M["deck"]))
    for z in ribs:
        hull.append(box("deckseam", (-HALF, 0.0, z - 0.01), (HALF, 0.003, z + 0.01), M["frame"]))
    # The forward bulkhead: the screen in a dark surround; the aft bulkhead with the hatch.
    hull.append(back_panel("bulkhead", 0.1, -1, ring, 0.05, M["hull"]))
    hull.append(box("surround", (-SCREEN_W / 2 - 0.12, SCREEN_MID - SCREEN_H / 2 - 0.12, 0.0), (SCREEN_W / 2 + 0.12, SCREEN_MID + SCREEN_H / 2 + 0.12, 0.05), M["frame"]))
    glows.append(box("screen", (-SCREEN_W / 2, SCREEN_MID - SCREEN_H / 2, -0.005), (SCREEN_W / 2, SCREEN_MID + SCREEN_H / 2, 0.0), M["screen"]))
    hull.append(back_panel("aft", BACK, 1, ring, 0.05, M["hull"]))
    hull.append(box("hatchring", (-0.75, 0.25, BACK), (0.75, 2.15, BACK + 0.12), M["frame"], bevel=0.08, segments=3))
    hull.append(box("hatch", (-0.6, 0.38, BACK + 0.08), (0.6, 2.02, BACK + 0.16), M["locker"], bevel=0.06, segments=3))
    hull.append(cylinder("wheel", 0, BACK + 0.22, 0.22, 1.15, 1.2, M["rail"], segments=20))
    things.append(box("photo", (0.95, 1.45, BACK + 0.06), (1.2, 1.62, BACK + 0.065), M["photo"]))
    things.append(box("tape", (1.03, 1.6, BACK + 0.066), (1.12, 1.64, BACK + 0.07), M["paper"]))
    # Handrails along both walls, on standoffs.
    for side in (1, -1):
        for y in (1.0, 2.1):
            things.append(rod("handrail", (side * (HALF - 0.12), y, -0.3), (side * (HALF - 0.12), y, BACK + 0.3), 0.018, M["rail"], sides=8))
            for z in ribs[1:-1]:
                things.append(rod("standoff", (side * (HALF - 0.05), y, z + 0.1), (side * (HALF - 0.12), y, z + 0.1), 0.012, M["rail"], sides=6))
    # LED strips along the crown's shoulders; status lights on the aft bulkhead.
    for side in (1, -1):
        x = side * (HALF - 0.35)
        glows.append(box("led", (x - 0.04, 2.62, BACK + 0.2), (x + 0.04, 2.64, -0.2), M["led"]))
        area("ledlight", (x, 2.58, (BACK - 0.2) / 2 + 0.1), abs(BACK) - 0.6, 160, (0.85, 0.92, 1.0), aim=(x * 0.3, 0, (BACK - 0.2) / 2), size_y=0.06)
    for i in range(6):
        glows.append(box("status", (-1.6 + i * 0.12, 2.3, BACK + 0.05), (-1.53 + i * 0.12, 2.36, BACK + 0.06), M["status"] if i % 3 else M["statusr"]))
    # Lockers along the lower walls behind you, with blue velcro patches.
    for side in (1, -1):
        for i, z in enumerate((-4.2, -5.0, -5.8)):
            x0, x1 = sorted((side * (HALF - 0.45), side * (HALF - 0.05)))
            things.append(box("locker", (x0, 0.0, z - 0.38), (x1, 0.5, z + 0.38), M["locker"], bevel=0.015, segments=2))
            things.append(box("velcro", (x0 if side < 0 else x0 - 0.002, 0.3, z - 0.1), (x0 + 0.002 if side < 0 else x0, 0.4, z + 0.1), M["blue"]))
    # A grow box of greens on your left wall, lit purple; a laptop on its arm on your right.
    gx = HALF - 0.4
    things.append(box("growbox", (gx - 0.05, 0.95, -4.25), (gx + 0.35, 1.25, -3.3), M["locker"], bevel=0.01, segments=1))
    rnd = random.Random(5)
    for k in range(36):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rnd.uniform(0.04, 0.07))
        bmesh.ops.translate(bm, vec=P(gx + rnd.uniform(0.0, 0.3), 1.25 + rnd.uniform(0.0, 0.12), rnd.uniform(-4.2, -3.35)), verts=bm.verts)
        things.append(_mesh_object("greens", bm, M["green"], smooth=True))
    glows.append(box("growlight", (gx - 0.02, 1.62, -4.2), (gx + 0.32, 1.64, -3.35), M["growlight"]))
    point("grow", (gx + 0.15, 1.55, -3.75), 12, (0.85, 0.4, 1.0), radius=0.1)
    lx = -(HALF - 0.1)
    things.append(rod("arm1", (lx, 1.3, -2.2), (lx + 0.5, 1.2, -2.0), 0.02, M["rail"], sides=6))
    things.append(rod("arm2", (lx + 0.5, 1.2, -2.0), (lx + 0.75, 1.15, -1.8), 0.02, M["rail"], sides=6))
    things.append(tilt(box("laptopbase", (lx + 0.6, 1.13, -2.0), (lx + 0.95, 1.15, -1.75), M["laptop"], bevel=0.005, segments=1), 0, (1.14, -1.9)))
    things.append(box("laptoplid", (lx + 0.6, 1.15, -2.02), (lx + 0.95, 1.38, -2.0), M["laptop"]))
    glows.append(box("laptopscreen", (lx + 0.62, 1.17, -1.999), (lx + 0.93, 1.36, -1.995), M["laptopscreen"]))
    # Cable runs along the ceiling's edge; things drifting free.
    for side in (1, -1):
        things.append(rod("cablerun", (side * (HALF - 0.2), 2.35, -0.2), (side * (HALF - 0.2), 2.35, BACK + 0.2), 0.03, M["cable"], sides=6))
    things.append(tilt(box("notebook", (0.9, 1.9, -1.4), (1.12, 1.92, -1.1), M["blue"], bevel=0.004, segments=1), 25, (1.91, -1.25)))
    things.append(rod("pen", (-0.8, 2.2, -2.8), (-0.68, 2.27, -2.7), 0.006, M["laptop"], sides=6))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.07)
    bmesh.ops.scale(bm, vec=(1.0, 0.5, 1.4), verts=bm.verts)
    bmesh.ops.translate(bm, vec=P(-1.3, 1.8, -3.4), verts=bm.verts)
    things.append(_mesh_object("pouch", bm, M["pouch"], smooth=True))
    return hull, things, glows


def main():
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 4
    s.cycles.diffuse_bounces = 3
    s.cycles.sample_clamp_indirect = 4.0
    # Orbit: black space, the sun through the right windows, the Earth's blue glow up through the left and below.
    s.world.node_tree.nodes["Background"].inputs[0].default_value = (0.0, 0.0, 0.0, 1)
    sun = bpy.data.lights.new("sun", 'SUN'); sun.energy = 2.5; sun.color = (1.0, 0.97, 0.92); sun.angle = math.radians(0.5)
    so = bpy.data.objects.new("sun", sun); bpy.context.collection.objects.link(so)
    so.rotation_mode = 'QUATERNION'; so.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(-1.0, 0.3, -0.3))).to_track_quat('-Z', 'Y')
    for side in (1, -1):
        area("earthglow", (side * (HALF + 0.3), 1.15, -2.5), 4.5, 90 if side > 0 else 40, (0.45, 0.65, 1.0), aim=(0, 1.0, -2.5), size_y=1.2)
    M = materials()
    hull, things, glows = build(M)
    groups = {"hull": join(hull, "hull"), "things": join(things, "things")}
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "1.0"))
    s.view_settings.exposure = math.log2(exposure)

    def view(k):
        return (0.0, EYE, -DISTANCES[k])
    views = {"ahead": (0, SCREEN_MID, 0), "left": (5, 1.3, -2.0), "right": (-5, 1.3, -2.0), "back": (0, 1.4, -20), "up": (0, 6, -2.3)}
    if mode == "preview":
        for k, aim in views.items():
            preview(view(2), aim, os.path.join(out, k + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return
    eyes = [Vector(P(dx, h, -d + dz)) for d in DISTANCES for dx in (-0.8, 0, 0.8) for h in (1.0, 1.7) for dz in (-0.4, 0.4)]
    occluders = scene_bvh(list(groups.values()) + [glow_obj])
    sizes = {"hull": 4096, "things": 2048}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {n: bake(o, sizes[n], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders) for n, o in groups.items()}
    for n, px in raw.items():
        finish(groups[n], px, out, exposure)
    export(list(groups.values()) + [glow_obj], os.path.join(out, "station.glb"), quality=86)
    with open(os.path.join(out, "station.json"), "w") as f:
        json.dump({"screen": {"width": SCREEN_W, "height": SCREEN_H, "middle": SCREEN_MID}}, f, indent=1)
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    for k in ("left", "back"):
        preview(view(2), views[k], os.path.join(out, "baked_" + k + ".png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
