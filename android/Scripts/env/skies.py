"""The new places' skies, rendered as 360° pictures round where you sit (equirectangular, 4096 x 2048).

    blender-env/bin/python skies.py OUT [drivein city winter sea]

drivein  a summer night over a field: the last glow low ahead, stars, a dark treeline all round.
city     a city at night from a rooftop: towers in rings out to the horizon, their windows lit, an orange glow on low cloud.
winter   a moonlit pine forest in snow: the moon, stars, snow on the ground glowing blue, pines all round.
sea      under the sea: light from the surface above in shafts, blue fading to deep below, rocks and kelp in the haze.

The picture's middle is ahead (the screen's side), as the other skies are.
"""
import sys
import os
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from envkit import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

W, H = (4096, 2048) if os.environ.get("QUALITY", "final") != "quick" else (1024, 512)


def world_gradient(top, horizon, bottom, strength=1.0, stars=0.0):
    w = bpy.context.scene.world
    nt = w.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_WORLD': nt.nodes.remove(n)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.47; els[0].color = (*bottom, 1)
    els[1].position = 0.68; els[1].color = (*top, 1)
    e = els.new(0.502); e.color = (*horizon, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[1].default_value = strength
    out = nt.nodes["World Output"]
    if stars > 0:
        vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 900
        vor.feature = 'DISTANCE_TO_EDGE' if False else 'F1'
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs[1].default_value = 0.0; mr.inputs[2].default_value = 0.05; mr.inputs[3].default_value = stars; mr.inputs[4].default_value = 0.0
        mr.clamp = True
        nt.links.new(coord.outputs["Generated"], vor.inputs["Vector"])
        nt.links.new(vor.outputs["Distance"], mr.inputs[0])
        above = nt.nodes.new("ShaderNodeMath"); above.operation = 'GREATER_THAN'; above.inputs[1].default_value = 0.52
        nt.links.new(sep.outputs["Z"], above.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'
        nt.links.new(mr.outputs[0], mul.inputs[0]); nt.links.new(above.outputs[0], mul.inputs[1])
        add = nt.nodes.new("ShaderNodeMixRGB"); add.blend_type = 'ADD'; add.inputs[0].default_value = 1.0
        nt.links.new(ramp.outputs["Color"], add.inputs[1]); nt.links.new(mul.outputs[0], add.inputs[2])
        nt.links.new(add.outputs[0], bg.inputs[0])
    else:
        nt.links.new(ramp.outputs["Color"], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])


def camera(eye_y=1.2):
    cam = bpy.data.cameras.new("pano"); cam.type = 'PANO'
    try:
        cam.panorama_type = 'EQUIRECTANGULAR'
    except Exception:
        cam.cycles.panorama_type = 'EQUIRECTANGULAR'
    o = bpy.data.objects.new("pano", cam); bpy.context.collection.objects.link(o)
    o.location = P(0, eye_y, 0)
    # Looking ahead (+z in the seat frame), level.
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Vector(P(0, 0, 1)).to_track_quat('-Z', 'Y')
    s = bpy.context.scene
    s.camera = o
    s.render.resolution_x, s.render.resolution_y = W, H
    return o


def pine(objs, mat, trunk, x, z, h, r):
    for k in range(4):
        y0 = h * (0.25 + 0.18 * k)
        rr = r * (1 - 0.22 * k)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=rr, radius2=0.0, depth=h * 0.42)
        bmesh.ops.translate(bm, vec=P(x, y0 + h * 0.21, z), verts=bm.verts)
        objs.append(_mesh_object("pine", bm, mat))
    objs.append(cylinder("trunk", x, z, r * 0.08, 0, h * 0.3, trunk, segments=6))


def ground(mat, size=3000, y=0.0):
    return box("ground", (-size, y - 0.1, -size), (size, y, size), mat)


def drivein():
    reset(48)
    world_gradient(top=(0.004, 0.006, 0.02), horizon=(0.10, 0.06, 0.08), bottom=(0.01, 0.01, 0.012), strength=1.0, stars=0.9)
    ground(material("field", (0.02, 0.025, 0.015), rough=1))
    r = random.Random(4)
    objs = []
    dark = material("trees", (0.004, 0.006, 0.004), rough=1)
    for k in range(260):
        a = r.uniform(0, 2 * math.pi); d = r.uniform(180, 260)
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r.uniform(6, 12))
        bmesh.ops.scale(bm, vec=(1, 1, r.uniform(0.9, 1.6)), verts=bm.verts)
        bmesh.ops.translate(bm, vec=P(d * math.sin(a), r.uniform(4, 10), d * math.cos(a)), verts=bm.verts)
        objs.append(_mesh_object("tree", bm, dark, smooth=True))
    # The screen's tower far ahead is the app's; here, the projection booth's glow behind and a few lamps by the road.
    lampm = glow("lamp", (1.0, 0.75, 0.4))
    for k in range(9):
        a = math.radians(140 + 10 * k); d = 120
        objs.append(cylinder("lamp", d * math.sin(a), d * math.cos(a), 0.6, 6, 7, lampm, segments=8))
    point("glowbooth", (0, 3, -60), 3000, (1.0, 0.7, 0.4), radius=2)
    camera(1.8)


def city():
    reset(48)
    world_gradient(top=(0.01, 0.012, 0.03), horizon=(0.30, 0.16, 0.08), bottom=(0.02, 0.02, 0.025), strength=1.0, stars=0.15)
    ground(material("streets", (0.03, 0.03, 0.035), rough=1), y=-40)
    r = random.Random(9)
    wall = material("towerwall", (0.02, 0.022, 0.028), rough=0.6)
    windows = bpy.data.materials.new("windows"); windows.use_nodes = True
    nt = windows.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.02, 0.02, 0.025, 1)
    brick = nt.nodes.new("ShaderNodeTexBrick"); brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.35; brick.offset = 0.0
    brick.inputs["Brick Width"].default_value = 1.6; brick.inputs["Row Height"].default_value = 3.4
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], brick.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexWhiteNoise"); noise.noise_dimensions = '3D'
    snap = nt.nodes.new("ShaderNodeVectorMath"); snap.operation = 'SNAP'; snap.inputs[1].default_value = (1.6, 1.6, 3.4)
    nt.links.new(coord.outputs["Object"], snap.inputs[0]); nt.links.new(snap.outputs[0], noise.inputs["Vector"])
    lit = nt.nodes.new("ShaderNodeMath"); lit.operation = 'GREATER_THAN'; lit.inputs[1].default_value = 0.78
    nt.links.new(noise.outputs["Value"], lit.inputs[0])
    pane = nt.nodes.new("ShaderNodeMath"); pane.operation = 'SUBTRACT'; pane.inputs[0].default_value = 1.0
    nt.links.new(brick.outputs["Fac"], pane.inputs[1])
    on = nt.nodes.new("ShaderNodeMath"); on.operation = 'MULTIPLY'
    nt.links.new(lit.outputs[0], on.inputs[0]); nt.links.new(pane.outputs[0], on.inputs[1])
    warm = nt.nodes.new("ShaderNodeMixRGB"); warm.inputs[1].default_value = (1.0, 0.75, 0.45, 1); warm.inputs[2].default_value = (0.75, 0.85, 1.0, 1)
    nt.links.new(noise.outputs["Color"], warm.inputs[0])
    strength = nt.nodes.new("ShaderNodeMath"); strength.operation = 'MULTIPLY'; strength.inputs[1].default_value = 1.4
    nt.links.new(on.outputs[0], strength.inputs[0])
    nt.links.new(warm.outputs[0], b.inputs["Emission Color"]); nt.links.new(strength.outputs[0], b.inputs["Emission Strength"])
    objs = []
    for ring, (dmin, dmax, n, hmax) in enumerate(((60, 160, 70, 120), (160, 400, 140, 220), (400, 900, 220, 300))):
        for k in range(n):
            a = r.uniform(0, 2 * math.pi); d = r.uniform(dmin, dmax)
            w = r.uniform(14, 40); h = r.uniform(20, hmax) * (0.6 + 0.4 * r.random())
            x, z = d * math.sin(a), d * math.cos(a)
            objs.append(box("tower", (x - w / 2, -40, z - w / 2), (x + w / 2, h - 40, z + w / 2), windows))
            if r.random() < 0.15:
                objs.append(glow("beacon%d" % len(objs), (1.0, 0.1, 0.05)) and cylinder("beacon", x, z, 0.8, h - 40, h - 38, glow("red%d" % k, (1.0, 0.1, 0.05)), segments=6))
    camera(1.2)


def winter():
    reset(48)
    world_gradient(top=(0.004, 0.008, 0.025), horizon=(0.05, 0.07, 0.12), bottom=(0.02, 0.03, 0.05), strength=1.0, stars=0.7)
    snow = material("snow", (0.85, 0.88, 0.95), rough=0.9)
    ground(snow)
    moon = bpy.data.lights.new("moon", 'SUN'); moon.energy = 0.9; moon.color = (0.7, 0.8, 1.0); moon.angle = math.radians(1)
    mo = bpy.data.objects.new("moon", moon); bpy.context.collection.objects.link(mo)
    mo.rotation_mode = 'QUATERNION'; mo.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(-0.5, 0.5, -0.7))).to_track_quat('-Z', 'Y')
    disc = glow("moondisc", (1.0, 1.0, 0.95))
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=3, radius=25)
    bmesh.ops.translate(bm, vec=P(-500, 500, -700), verts=bm.verts)
    _mesh_object("moondisc", bm, disc, smooth=True)
    r = random.Random(12)
    needles = material("needles", (0.02, 0.05, 0.03), rough=0.9)
    snowy = material("snowypine", (0.55, 0.6, 0.68), rough=0.9)
    bark = material("bark", (0.06, 0.04, 0.03), rough=0.9)
    objs = []
    for k in range(420):
        a = r.uniform(0, 2 * math.pi); d = r.uniform(14, 220) ** 1.0
        if d < 14: continue
        h = r.uniform(6, 16)
        pine(objs, snowy if r.random() < 0.6 else needles, bark, d * math.sin(a), d * math.cos(a), h, h * 0.28)
    camera(1.2)


def sea():
    reset(48)
    world_gradient(top=(0.35, 0.75, 0.85), horizon=(0.04, 0.25, 0.38), bottom=(0.01, 0.05, 0.08), strength=1.3)
    s = bpy.context.scene
    sand = textured("sand", (0.30, 0.32, 0.26), (0.18, 0.20, 0.16), "carpet", scale=0.2, rough=1)
    ground(sand, y=-0.5)
    # Light from the surface: a broad sun straight down, blue-green, and shafts as long thin glowing columns fading.
    sun = bpy.data.lights.new("surface", 'SUN'); sun.energy = 2.5; sun.color = (0.6, 0.9, 1.0); sun.angle = math.radians(20)
    so = bpy.data.objects.new("surface", sun); bpy.context.collection.objects.link(so)
    so.rotation_mode = 'QUATERNION'; so.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(0.2, 1, 0.3))).to_track_quat('-Z', 'Y')
    r = random.Random(21)
    rock = textured("rock", (0.10, 0.12, 0.11), (0.04, 0.05, 0.05), "carpet", scale=0.5, rough=1, bump=0.5)
    kelp = material("kelp", (0.10, 0.18, 0.05), rough=0.8)
    shaft = bpy.data.materials.new("shaft"); shaft.use_nodes = True
    nt = shaft.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL': nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs[0].default_value = (0.5, 0.85, 1.0, 1); em.inputs[1].default_value = 0.035
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(em.outputs[0], mix.inputs[0]); nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    for k in range(70):
        a = r.uniform(0, 2 * math.pi); d = r.uniform(15, 90)
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r.uniform(2, 8))
        bmesh.ops.scale(bm, vec=(1, 1, r.uniform(0.4, 0.9)), verts=bm.verts)
        bmesh.ops.translate(bm, vec=P(d * math.sin(a), -0.5, d * math.cos(a)), verts=bm.verts)
        _mesh_object("rock", bm, rock, smooth=True)
    for k in range(160):
        a = r.uniform(0, 2 * math.pi); d = r.uniform(10, 70)
        x, z = d * math.sin(a), d * math.cos(a)
        h = r.uniform(5, 18)
        for j in range(8):
            cylinder("kelp", x + 0.4 * math.sin(j * 0.7), z, 0.15, -0.5 + j * h / 8, -0.5 + (j + 1) * h / 8, kelp, segments=5)
    # The water's haze, within 150 m (a world-wide one would swallow the light from beyond): distance fades into blue.
    hm = bpy.data.materials.new("haze"); hm.use_nodes = True
    hn = hm.node_tree
    for n in list(hn.nodes):
        if n.type != 'OUTPUT_MATERIAL': hn.nodes.remove(n)
    vol = hn.nodes.new("ShaderNodeVolumeScatter"); vol.inputs["Density"].default_value = 0.008; vol.inputs["Color"].default_value = (0.25, 0.65, 0.8, 1)
    hn.links.new(vol.outputs[0], hn.nodes["Material Output"].inputs["Volume"])
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=3, radius=150)
    _mesh_object("haze", bm, hm)
    camera(1.2)


def main():
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    which = sys.argv[2:] or ["drivein", "city", "winter", "sea"]
    for name in which:
        globals()[name]()
        s = bpy.context.scene
        s.cycles.samples = 48 if W > 2000 else 16
        s.view_settings.view_transform = 'Standard'
        s.render.image_settings.file_format = 'JPEG'; s.render.image_settings.quality = 88
        s.render.filepath = os.path.join(out, "lumiere_%s.jpg" % name)
        bpy.ops.render.render(write_still=True)
        log("sky", name)


if __name__ == "__main__":
    main()
