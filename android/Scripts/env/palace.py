"""Lumiere's picture palace: a 1930s Art Deco cinema on the cinema's own rows, modelled and lit, its light baked.

    blender-env/bin/python palace.py preview OUT  |  bake OUT   (QUALITY=quick for a try)

The same stadium of seats and the same screen as the cinema (CinemaHall on the
Quest, so every seat and sightline holds), dressed as a picture palace: deep
teal walls between gilt fins, the seats in burgundy velvet, a teal and gold
carpet, champagne-gold drapes and valance, a great gold sunburst over the
proscenium inside three stepped gilt arches, and gilt rings across the
ceiling round a glowing chandelier. Out to palace.glb and palace_curtain.glb.
"""
import sys
import os
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cinema  # noqa: E402
from cinema import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402
import bmesh  # noqa: E402


def restyle(M):
    def recolour(m, a, b=None):
        nt = m.node_tree
        for n in nt.nodes:
            if n.type == 'VALTORGB':
                n.color_ramp.elements[0].color = (*a, 1)
                n.color_ramp.elements[1].color = (*(b or a), 1)
            if n.type == 'BSDF_PRINCIPLED' and not any(l.to_node == n and l.to_socket.name == "Base Color" for l in nt.links):
                n.inputs["Base Color"].default_value = (*a, 1)
    recolour(M["fabric"], (0.025, 0.075, 0.075), (0.015, 0.05, 0.052))
    recolour(M["walnut"], (0.50, 0.34, 0.11), (0.36, 0.23, 0.07))
    recolour(M["drape"], (0.52, 0.40, 0.20), (0.36, 0.26, 0.12))
    recolour(M["carpet"], (0.03, 0.085, 0.085), (0.22, 0.15, 0.05))
    recolour(M["velvet"], (0.26, 0.02, 0.04), (0.17, 0.012, 0.025))
    recolour(M["ceiling"], (0.012, 0.035, 0.038))
    recolour(M["wall"], (0.02, 0.05, 0.05))
    recolour(M["brass"], (0.58, 0.42, 0.14))
    recolour(M["fringe"], (0.62, 0.45, 0.15), (0.40, 0.28, 0.08))


def extra(M, hall, glows):
    gilt = M["brass"]
    # Three stepped gilt arches round the proscenium, each a frame standing a little prouder.
    for i, grow in enumerate((0.0, 0.55, 1.1)):
        half = STAGE_HALF + 0.25 + grow
        top = OPENING_TOP + 0.3 + grow * 0.8
        z = PROSCENIUM - 0.12 - 0.06 * i
        for side in (1, -1):
            x0, x1 = sorted((side * half, side * (half + 0.22)))
            hall.append(box("arch", (x0, 0.0, z - 0.06), (x1, top, z), gilt, bevel=0.02, segments=2))
        hall.append(box("archtop", (-half - 0.22, top, z - 0.06), (half + 0.22, top + 0.22, z), gilt, bevel=0.02, segments=2))
    # A sunburst over the valance: rays fanning up from a half-disc.
    cx, cy, cz = 0.0, OPENING_TOP + 0.35, PROSCENIUM - 0.3
    n = 23
    for k in range(n):
        a = math.pi * (k + 0.5) / n
        length = 1.9 if k % 2 == 0 else 1.3
        bm = bmesh.new()
        w = 0.07
        pts = [(cx + 0.55 * math.cos(a) - w * math.sin(a), cy + 0.55 * math.sin(a) + w * math.cos(a)),
               (cx + length * math.cos(a), cy + length * math.sin(a)),
               (cx + 0.55 * math.cos(a) + w * math.sin(a), cy + 0.55 * math.sin(a) - w * math.cos(a))]
        vs = [bm.verts.new(P(x, y, cz)) for x, y in pts]
        bm.faces.new(vs)
        o = _mesh_object("ray", bm, gilt)
        o.modifiers.new("t", 'SOLIDIFY').thickness = 0.03
        hall.append(o)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=32, radius=0.55)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(P(cx, cy, cz)) @ Matrix.Rotation(math.radians(90), 4, 'X'), verts=bm.verts)
    disc = _mesh_object("sun", bm, gilt)
    disc.modifiers.new("t", 'SOLIDIFY').thickness = 0.05
    hall.append(disc)
    # Gilt rings across the front ceiling round a chandelier of glowing glass.
    y = TIERS[0][2] - 0.02
    cz2 = -4.2
    for r in (1.2, 2.2, 3.2):
        segs = 48
        pts = [(r * math.cos(2 * math.pi * i / segs), y, cz2 + r * math.sin(2 * math.pi * i / segs)) for i in range(segs + 1)]
        for p0, p1 in zip(pts, pts[1:]):
            hall.append(rod("ring", p0, p1, 0.04, gilt, sides=6))
    hall.append(rod("chain", (0, y, cz2), (0, y - 1.6, cz2), 0.02, gilt, sides=6))
    glass = lamp("chandelier", (1.0, 0.86, 0.62))
    for tier, (rr, yy) in enumerate(((0.65, y - 1.6), (0.45, y - 2.0), (0.25, y - 2.35))):
        for i in range(12):
            a = 2 * math.pi * i / 12
            glows.append(cylinder("drop", rr * math.cos(a), cz2 + rr * math.sin(a), 0.035, yy - 0.3, yy, glass, segments=8))
    point("chandelier", (0, y - 2.0, cz2), 400, (1.0, 0.8, 0.55), radius=0.5)


if __name__ == "__main__":
    cinema.main("palace", restyle, extra)
