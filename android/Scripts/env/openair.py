"""The common bake for open-air places round you (drivein.py, rooftop.py, sea.py): you at the origin, x left, y up, z ahead.

build(M) gives (ground, things, glows); light(scene) sets the world and the sun or moon.
"""
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from envkit import *  # noqa: E402,F401,F403
from mathutils import Vector, Matrix  # noqa: E402,F401

QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)


def sun(name, energy, color, toward, angle=2.0):
    """A sun (or moon) shining from the direction [toward] (seat frame)."""
    l = bpy.data.lights.new(name, 'SUN'); l.energy = energy; l.color = color; l.angle = math.radians(angle)
    o = bpy.data.objects.new(name, l); bpy.context.collection.objects.link(o)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(*toward))).to_track_quat('-Z', 'Y')


def main(name, materials, build, light, eye=(0.0, 1.15, 0.0), exposure=1.0, sizes=None, info=None):
    mode, out = sys.argv[-2], os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 4
    s.cycles.diffuse_bounces = 3
    s.cycles.sample_clamp_indirect = 4.0
    light(s)
    M = materials()
    ground, things, glows = build(M)
    groups = {"ground": join(ground, "ground"), "things": join(things, "things")}
    glow_obj = join(glows, "lights") if glows else None
    allobj = list(groups.values()) + ([glow_obj] if glow_obj else [])
    log("triangles", {k: triangles([o]) for k, o in groups.items()})
    exposure = float(os.environ.get("EXPOSURE", str(exposure)))
    s.view_settings.exposure = math.log2(exposure)
    views = {"ahead": (0, eye[1] - 0.2, 10), "left": (5, 0.6, 0), "right": (-5, 0.6, 0), "back": (0, 0.9, -10)}
    if mode == "preview":
        for k, aim in views.items():
            preview(eye, aim, os.path.join(out, k + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return
    eyes = [Vector(P(eye[0] + dx, eye[1] + dh, eye[2] + dz)) for dx in (-1.0, 0, 1.0) for dh in (-0.15, 0.5) for dz in (-0.5, 0, 0.5)]
    occluders = scene_bvh(allobj)
    sizes = sizes or {"ground": 2048, "things": 4096}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    raw = {n: bake(o, sizes[n], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders) for n, o in groups.items()}
    for n, px in raw.items():
        finish(groups[n], px, out, exposure)
    export(allobj, os.path.join(out, name + ".glb"), quality=86)
    with open(os.path.join(out, name + ".json"), "w") as f:
        json.dump(info or {}, f, indent=1)
