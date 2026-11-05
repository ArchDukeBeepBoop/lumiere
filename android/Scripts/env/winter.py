"""Lumiere's winter cabin: the cabin's great room on a moonlit night in deep snow, its light baked.

    blender-env/bin/python winter.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

The cabin's own room round its own screen (CabinRoom on the Quest, so the
sofa and every size hold; it borrows cabin_sofa.glb), turned to winter:
paler, colder timber, a deep red rug and throws, snow banked against the
glass and drifted along the sill outside, snowy pines beyond, and cold blue
moonlight through the glass against the fire's warmth. Out to winter.glb.
"""
import sys
import os
import math
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cabin  # noqa: E402
from cabin import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402
import bmesh  # noqa: E402

MOON = (0.55, 0.68, 1.0)


def restyle(M):
    def recolour(m, a, b=None):
        nt = m.node_tree
        for n in nt.nodes:
            if n.type == 'VALTORGB':
                n.color_ramp.elements[0].color = (*a, 1)
                n.color_ramp.elements[1].color = (*(b or a), 1)
            if n.type == 'BSDF_PRINCIPLED' and not any(l.to_node == n and l.to_socket.name == "Base Color" for l in nt.links):
                n.inputs["Base Color"].default_value = (*a, 1)
    recolour(M["batten"], (0.20, 0.14, 0.10), (0.13, 0.09, 0.06))
    recolour(M["beam"], (0.38, 0.27, 0.18), (0.26, 0.18, 0.11))
    recolour(M["plaster"], (0.52, 0.50, 0.47), (0.46, 0.44, 0.41))
    for k in ("rug", "wool"):
        if k in M: recolour(M[k], (0.32, 0.04, 0.05), (0.20, 0.025, 0.03))
    w = bpy.context.scene.world.node_tree.nodes["Background"]
    w.inputs[0].default_value = (0.04, 0.06, 0.13, 1)


def extra(M, hall, left, right, glows):
    snow = material("snow", (0.82, 0.86, 0.92), rough=0.9)
    pine = material("pine", (0.03, 0.07, 0.05), rough=0.9)
    r = random.Random(7)
    x0 = -HALF - 0.2
    # The snowfield beyond the glass, rising in drifts against it.
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=24, y_segments=40, size=1.0)
    for v in bm.verts:
        u, w = v.co.x, v.co.y            # -1..1
        x = x0 - (u + 1) * 12
        z = BACK + (w + 1) / 2 * (WALL_FACE - BACK + 8) - 4
        drift = 0.55 * math.exp(-(x0 - x) / 1.2) + 0.12 * math.sin(z * 0.9 + x * 0.4)
        v.co = Vector(P(x, drift, z))
    right.append(_mesh_object("snowfield", bm, snow, smooth=True))
    # Snow piled along the sill outside each pane.
    right.append(box("sill", (x0 - 0.35, 0.0, BACK + 0.2), (x0, 0.28, WALL_FACE - 0.2), snow, bevel=0.12, segments=3))
    # Snowy pines: tiers of cones, white-capped.
    for i in range(9):
        px = x0 - r.uniform(4, 22)
        pz = r.uniform(BACK - 4, 6)
        h = r.uniform(4, 8)
        right.append(cylinder("ptrunk", px, pz, 0.15, 0, h * 0.25, M["beam"], segments=8))
        for t in range(4):
            y0 = h * (0.2 + 0.2 * t)
            rr = h * (0.28 - 0.055 * t)
            for mat, dy, sc in ((pine, 0, 1.0), (snow, 0.12, 0.8)):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=rr * sc, radius2=0.02, depth=h * 0.3 * sc)
                bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90), 4, 'X'), verts=bm.verts)
                bmesh.ops.translate(bm, vec=P(px, y0 + dy + h * 0.15 * sc, pz), verts=bm.verts)
                right.append(_mesh_object("pine", bm, mat))
    # The moon outside: the dusk panels turn cold and bright, a moon from high on the right.
    for l in bpy.data.lights:
        if l.name.startswith("dusk"):
            l.color = MOON
            l.energy *= 0.7
    moon = bpy.data.lights.new("moon", 'SUN'); moon.energy = 0.5; moon.color = MOON; moon.angle = math.radians(1)
    mo = bpy.data.objects.new("moon", moon); bpy.context.collection.objects.link(mo)
    mo.rotation_mode = 'QUATERNION'
    mo.rotation_quaternion = (Vector(P(0, 0, 0)) - Vector(P(-1, 0.8, 0.3))).to_track_quat('-Z', 'Y')


if __name__ == "__main__":
    cabin.main("winter", restyle, extra, with_sofa=False)
