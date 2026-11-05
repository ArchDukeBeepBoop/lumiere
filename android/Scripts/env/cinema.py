"""Lumiere's cinema: a stadium picture house, modelled and lit, its light baked.

    blender-env/bin/python cinema.py preview OUT     the hall lit in Cycles, from the five seats
    blender-env/bin/python cinema.py bake OUT        baked, exported to OUT/cinema.glb (+ the curtain)
    QUALITY=quick ...                                  small atlases and few samples, to try things

One fixed hall round one 20 m screen (16:9, its foot 1.1 m above the front
floor): twelve rows of thirty-three velvet seats stepping up 38 cm a row
from a balcony front 2 m above the pit, so the screen's middle is a little
above your eyes from the middle rows and below them from the back. The five
screen sizes are five seats in it (SEAT_ROWS): the back row's screen fills
55° of your view, the front row's 115°.

Laid out in the seat frame the app uses (envkit.P): x to your left, y up, z
toward the screen; the origin on the front floor under the screen's middle,
the screen's face at z = 0. The headset puts the hall round you by the row
you sit in (CinemaHall on the Quest, which reads cinema.json written here).

Everything is lit as a real hall is — warm sconces washing the panelled walls
in scallops, coves glowing in the ceiling's steps, downlights, step lights in
the aisles, footlights on the drapes — and Cycles bakes it, soft shadows and
the light bounced off every wall, into a few atlases. The headset draws them
unlit and dims them for a film; lamps and signs are their own materials
("lamp:" dims with the house lights, "glow:" stays lit).
"""
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from envkit import *  # noqa: E402,F401,F403
from envkit import _mesh_object  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

# --- The hall's numbers -------------------------------------------------------------------

SCREEN_W, SCREEN_H = 20.0, 11.25
SCREEN_BOTTOM = 1.1
SCREEN_MID = SCREEN_BOTTOM + SCREEN_H / 2
ROWS, PITCH, NEAREST = 12, 1.15, 6.37
RAKE, FIRST_FLOOR = 0.38, 1.98
EYE = 1.2
SEAT_ROWS = [11, 7, 4, 2, 0]          # the five sizes, smallest (the back row) first
SEATS, SEAT_PITCH = 33, 0.66
SEAT_BACK_FROM_EYE = 0.2               # a seat's origin is this far ahead of the eyes of whoever sits in it
HALF = 12.8                            # the side walls' faces
AISLE = 11.05                          # where the seating ends and the side aisles begin
BACK = -21.8                           # the back wall's face
STAGE_FRONT, STAGE_TOP, STAGE_HALF = -2.2, 0.9, 11.2
PROSCENIUM = -0.8                      # the proscenium wall's face; the opening is STAGE_HALF wide, up to OPENING_TOP
OPENING_TOP = 13.2
CURTAIN_Z, CURTAIN_RISE = -0.45, 14.5
TIERS = [(-7.5, PROSCENIUM, 14.6), (-14.5, -7.5, 13.6), (BACK, -14.5, 12.6)]   # the ceiling's steps: from z, to z, height
FLIGHT_FOOT = -2.4                     # the aisle stairs' first step, up from the pit to the front row


def dist(k): return NEAREST + PITCH * k
def floor_of(k): return FIRST_FLOOR + RAKE * k
def eye_z(k): return -dist(k)
def back_edge(k): return eye_z(k) - 0.60      # where row k's platform meets the riser up to the row behind


PARAPET_Z = eye_z(0) + 0.75             # the balcony front, the seating's foremost edge
PARAPET_H = 0.78                        # its top above the front row's floor, under every front-row sightline to the screen's foot
SEAT_TOP, SEAT_TOP_BEHIND_EYE = 1.04, 0.33   # a seat back's top above its floor, and how far behind its sitter's eyes


def line(z):
    """The aisles' stair line along the walls, front to back: the pit, the flight up to the front row,
    then the rows' rake to the top cross-aisle."""
    if z >= FLIGHT_FOOT: return 0.0
    if z >= PARAPET_Z: return FIRST_FLOOR * (FLIGHT_FOOT - z) / (FLIGHT_FOOT - PARAPET_Z)
    if z >= back_edge(ROWS - 1):
        return FIRST_FLOOR + (PARAPET_Z - z) * (floor_of(ROWS - 1) - FIRST_FLOOR) / (PARAPET_Z - back_edge(ROWS - 1))
    return floor_of(ROWS - 1)


def ceiling_at(z):
    for z0, z1, y in TIERS:
        if z0 - 1e-6 <= z <= z1 + 1e-6: return y
    return TIERS[-1][2]


QUICK = os.environ.get("QUALITY", "final") == "quick"
RES = (960, 540) if QUICK else (1600, 900)
WARM = (1.0, 0.70, 0.42)
SOFT = (1.0, 0.80, 0.60)


# --- Materials ----------------------------------------------------------------------------

def materials():
    M = {}
    M["velvet"] = textured("velvet", (0.30, 0.024, 0.032), (0.21, 0.013, 0.02), "cloth", scale=7, rough=0.9)
    M["shell"] = material("shell", (0.036, 0.032, 0.03), rough=0.5)
    M["leather"] = material("leather", (0.017, 0.013, 0.012), rough=0.45)
    M["ring"] = material("cupring", (0.22, 0.22, 0.23), rough=0.3)
    M["hole"] = material("cuphole", (0.004, 0.004, 0.004), rough=1)
    M["carpet"] = textured("carpet", (0.085, 0.016, 0.022), (0.03, 0.007, 0.011), "carpet", scale=1.4, rough=1)
    M["walnut"] = textured("walnut", (0.12, 0.06, 0.03), (0.06, 0.028, 0.014), "wood", scale=0.7, rough=0.5)
    M["fabric"] = textured("wallcloth", (0.06, 0.05, 0.044), (0.04, 0.034, 0.03), "cloth", scale=3, rough=1)
    M["wall"] = material("wallplain", (0.035, 0.031, 0.029), rough=0.9)
    M["ceiling"] = material("ceiling", (0.02, 0.02, 0.024), rough=0.9)
    M["velour"] = material("velour", (0.006, 0.006, 0.006), rough=1)
    M["screen"] = lamp("screen", (0.075, 0.075, 0.08))   # the picture covers it; bare, a dim grey that dims with the hall
    M["brass"] = material("brass", (0.42, 0.27, 0.09), rough=0.35)
    M["drape"] = textured("drape", (0.27, 0.02, 0.03), (0.15, 0.009, 0.017), "cloth", scale=5, rough=0.9)
    M["fringe"] = textured("fringe", (0.45, 0.30, 0.10), (0.22, 0.13, 0.04), "wood", scale=6, rough=0.6)
    M["speaker"] = material("speaker", (0.013, 0.013, 0.013), rough=0.8)
    M["nosing"] = material("nosing", (0.2, 0.2, 0.21), rough=0.4)
    M["stage"] = material("stagefloor", (0.02, 0.018, 0.017), rough=0.6)
    M["exit"] = glow("exit", (0.12, 1.0, 0.4))
    M["step"] = glow("step", (1.0, 0.64, 0.32))
    M["booth"] = glow("booth", (0.55, 0.46, 0.34))
    M["sconce"] = lamp("sconce", (1.0, 0.84, 0.62))
    M["down"] = lamp("down", (1.0, 0.92, 0.78))
    M["foot"] = lamp("foot", (1.0, 0.72, 0.42))
    return M


# --- Shapes -------------------------------------------------------------------------------

def rod(name, a, b, r, mat, sides=10):
    """A round bar from [a] to [b] (seat frame): a handrail, a bracket."""
    va, vb = Vector(P(*a)), Vector(P(*b))
    d = vb - va
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r, radius2=r, depth=d.length)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=Matrix.Translation((va + vb) / 2) @ q.to_matrix().to_4x4(), verts=bm.verts)
    o = _mesh_object(name, bm, mat, smooth=True)
    return o


def seat_template(M):
    """One seat (without the arms between seats, which are shared): its velvet cushion and two-part back
    in a hard shell, leaning back 13°, round the origin on the floor, facing the screen."""
    parts = [
        tilt(box("cushion", (-0.28, 0.36, -0.30), (0.28, 0.49, 0.22), M["velvet"], bevel=0.045, segments=2), 4, (0.40, -0.30)),
        box("pan", (-0.27, 0.22, -0.28), (0.27, 0.37, 0.18), M["shell"], bevel=0.02, segments=1),
        tilt(box("lumbar", (-0.275, 0.44, -0.40), (0.275, 0.72, -0.27), M["velvet"], bevel=0.04, segments=2), 13, (0.42, -0.30)),
        tilt(box("upper", (-0.275, 0.735, -0.40), (0.275, 1.04, -0.27), M["velvet"], bevel=0.045, segments=2), 13, (0.42, -0.30)),
        tilt(box("shell", (-0.30, 0.40, -0.47), (0.30, 1.07, -0.385), M["shell"], bevel=0.025, segments=2), 13, (0.42, -0.30)),
        tilt(box("wingL", (0.272, 0.42, -0.43), (0.30, 1.06, -0.30), M["shell"], bevel=0.01, segments=1), 13, (0.42, -0.30)),
        tilt(box("wingR", (-0.30, 0.42, -0.43), (-0.272, 1.06, -0.30), M["shell"], bevel=0.01, segments=1), 13, (0.42, -0.30)),
    ]
    return join(parts, "seat_template")


def arm_template(M, end=False):
    """The standard between two seats with its padded arm and a cup holder; at a row's end, a taller
    panel with a little light by your feet."""
    if end:
        parts = [box("standard", (-0.04, 0.0, -0.50), (0.04, 0.92, 0.22), M["shell"], bevel=0.02, segments=2)]
    else:
        parts = [box("standard", (-0.035, 0.0, -0.40), (0.035, 0.60, 0.16), M["shell"], bevel=0.015, segments=1)]
    parts += [
        box("arm", (-0.05, 0.60 if not end else 0.62, -0.38), (0.05, 0.67 if not end else 0.69, 0.20), M["leather"], bevel=0.028, segments=2),
        cylinder("ring", 0, 0.115, 0.043, 0.655, 0.682 if not end else 0.702, M["ring"], segments=10),
        cylinder("hole", 0, 0.115, 0.034, 0.66, 0.684 if not end else 0.704, M["hole"], segments=10),
    ]
    return join(parts, "arm_template" + ("_end" if end else ""))


def shifted(o, dx):
    o.data.transform(Matrix.Translation(P(dx, 0, 0)))
    return o


def seats(M, rows, name):
    """The rows' seats as one object, each seat with the arm on its left one unit with its own layout,
    every unit a cell of the atlas: the row's leftmost seat has the row's end standard on its left, and the
    other end standard is a unit of its own."""
    unit = unwrap_unit(join([seat_template(M), shifted(arm_template(M), SEAT_PITCH / 2)], "unit"))
    unit_end = unwrap_unit(join([seat_template(M), shifted(arm_template(M, end=True), SEAT_PITCH / 2)], "unit_end"))
    end_r = unwrap_unit(shifted(arm_template(M, end=True), -SEAT_PITCH / 2))
    inner, lefts, rights = [], [], []
    for k in rows:
        y, z = floor_of(k), eye_z(k) + SEAT_BACK_FROM_EYE
        for i in range(SEATS):
            x = (i - (SEATS - 1) / 2) * SEAT_PITCH
            (lefts if i == SEATS - 1 else inner).append((x, y, z))
            if i == 0: rights.append((x, y, z))
    cells = len(inner) + len(lefts) + len(rights)
    grid = math.ceil(math.sqrt(cells))
    objs = [copies(unit, inner, name + "_seats", grid, 0),
            copies(unit_end, lefts, name + "_lefts", grid, len(inner)),
            copies(end_r, rights, name + "_rights", grid, len(inner) + len(lefts))]
    for t in (unit, unit_end, end_r): bpy.data.objects.remove(t)
    log(name, cells, "seats' cells in a", grid, "square grid")
    return join(objs, name), rights


def tiles(M, x, inward, z0, z1, bottom, top, tall, depth=0.05, gap=0.025, name="tile"):
    """Upholstered panels down a side wall's bay, from [top] down to a sloped [bottom](z)."""
    out = []
    y = top
    while True:
        lo = y - tall
        b0, b1 = bottom(z0) + gap, bottom(z1) + gap
        if lo <= max(b0, b1) + 0.35:
            # The last one, down to the slope.
            corners = [(z0, b0), (z0, y - gap), (z1, y - gap), (z1, b1)]
            if y - gap > max(b0, b1) + 0.05:
                out.append(panel(name, x, inward, corners, depth, M["fabric"], bevel=0.012, segments=2))
            break
        out.append(panel(name, x, inward, [(z0, lo), (z0, y - gap), (z1, y - gap), (z1, lo)], depth, M["fabric"], bevel=0.012, segments=2))
        y = lo
    return out


# --- The hall -----------------------------------------------------------------------------

def build(M):
    hall, rows, sides, glows, curtain = [], [], {1: [], -1: []}, [], []

    # The seating: the balcony front up from the pit, then each row's platform and the riser to the next.
    pts = [(PARAPET_Z, 0.0), (PARAPET_Z, FIRST_FLOOR)]
    for k in range(ROWS):
        pts.append((back_edge(k), floor_of(k)))
        if k + 1 < ROWS: pts.append((back_edge(k), floor_of(k + 1)))
    rows.append(profile("rows", -AISLE, AISLE, pts, M["carpet"], floor=-0.1))
    for k in range(1, ROWS):
        z = back_edge(k - 1)
        rows.append(box("nosing", (-AISLE, floor_of(k) - 0.025, z - 0.03), (AISLE, floor_of(k) + 0.004, z + 0.004), M["nosing"]))
    # The balcony front's parapet, walnut with a rounded cap.
    hall.append(box("parapet", (-AISLE, FIRST_FLOOR, PARAPET_Z - 0.14), (AISLE, FIRST_FLOOR + PARAPET_H - 0.06, PARAPET_Z), M["walnut"], bevel=0.01, segments=1))
    hall.append(box("parapetcap", (-AISLE - 0.02, FIRST_FLOOR + PARAPET_H - 0.06, PARAPET_Z - 0.18), (AISLE + 0.02, FIRST_FLOOR + PARAPET_H, PARAPET_Z + 0.02), M["walnut"], bevel=0.025, segments=3))
    # The top cross-aisle behind the back row, wall to wall.
    hall.append(box("crossaisle", (-HALF, floor_of(ROWS - 1) - 0.2, BACK), (HALF, floor_of(ROWS - 1), back_edge(ROWS - 1)), M["carpet"]))
    # The pit, from the balcony front to the proscenium.
    hall.append(box("pit", (-HALF, -0.1, PARAPET_Z - 0.01), (HALF, 0.0, PROSCENIUM), M["carpet"]))

    # Each side: the aisle's stairs, the wall, its panels and lights.
    for side in (1, -1):
        x_wall = side * HALF
        inward = -side
        s = sides[side]
        # Stairs: eleven steps up from the pit to the front row, then two to each row.
        st = [(FLIGHT_FOOT, 0.0)]
        n = 11
        for i in range(n):
            z0 = FLIGHT_FOOT + (PARAPET_Z - FLIGHT_FOOT) * i / n
            z1 = FLIGHT_FOOT + (PARAPET_Z - FLIGHT_FOOT) * (i + 1) / n
            y1 = FIRST_FLOOR * (i + 1) / n
            st += [(z0, y1), (z1, y1)]
        for k in range(1, ROWS):
            zb = back_edge(k - 1)
            half = floor_of(k - 1) + RAKE / 2
            st += [(zb + PITCH / 4, floor_of(k - 1)), (zb + PITCH / 4, half), (zb - PITCH / 4, half), (zb - PITCH / 4, floor_of(k))]
        st.append((back_edge(ROWS - 1), floor_of(ROWS - 1)))
        s.append(profile("stairs", side * AISLE, x_wall, st, M["carpet"], floor=-0.1))
        # A step light in every riser, and a nosing on each.
        risers = [(st[i][0], st[i][1], st[i + 1][1]) for i in range(len(st) - 1) if abs(st[i][0] - st[i + 1][0]) < 1e-6 and st[i + 1][1] > st[i][1]]
        xm = side * (AISLE + HALF) / 2
        for (z, y0, y1) in risers:
            s.append(box("stepnosing", (side * AISLE, y1 - 0.02, z - 0.03), (x_wall, y1 + 0.004, z + 0.004), M["nosing"]))
            glows.append(box("steplight", (xm - 0.07, y0 + 0.04, z + 0.004), (xm + 0.07, y0 + 0.07, z + 0.012), M["step"]))
            point("step", (xm, y0 + 0.06, z + 0.06), 1.2, (1.0, 0.62, 0.3), radius=0.02)
        # The wall: from under the stairs to the ceiling's steps.
        top = []
        for z0, z1, y in TIERS:
            top += [(z1, y + 0.2), (z0, y + 0.2)]
        bottom = [(BACK, floor_of(ROWS - 1) - 0.4), (back_edge(ROWS - 1), floor_of(ROWS - 1) - 0.4), (PARAPET_Z, FIRST_FLOOR - 0.4),
                  (FLIGHT_FOOT, -0.4), (PROSCENIUM, -0.4)]
        outline = [(PROSCENIUM, -0.4)] + top + bottom[:-1]
        s.append(panel("wall", x_wall + side * 0.1, inward, outline, 0.1, M["wall"]))
        # Walnut wainscot below a cap rail, in panels.
        zs = [PROSCENIUM - 0.02]
        while zs[-1] - 1.6 > BACK: zs.append(zs[-1] - 1.6)
        zs.append(BACK)
        for a, b in zip(zs, zs[1:]):
            s.append(panel("wainscot", x_wall, inward, [(a - 0.01, line(a) - 0.3), (a - 0.01, line(a) + 1.0), (b + 0.01, line(b) + 1.0), (b + 0.01, line(b) - 0.3)],
                           0.03, M["walnut"], bevel=0.006, segments=1))
        cap = []
        for a, b in zip(zs, zs[1:]):
            cap.append(panel("caprail", x_wall, inward, [(a, line(a) + 1.0), (a, line(a) + 1.07), (b, line(b) + 1.07), (b, line(b) + 1.0)], 0.06, M["walnut"], bevel=0.012, segments=2))
        s += cap
        # Walnut fins between the bays; upholstered panels in each bay; a speaker high in each.
        fins = [-2.3 - 3.0 * j for j in range(7)]
        for zf in fins:
            s.append(panel("fin", x_wall, inward, [(zf + 0.08, line(zf) + 1.07), (zf + 0.08, 12.05), (zf - 0.08, 12.05), (zf - 0.08, line(zf) + 1.07)],
                           0.2, M["walnut"], bevel=0.015, segments=2))
        bays = [(PROSCENIUM - 0.05, fins[0] + 0.1)] + [(a - 0.1, b + 0.1) for a, b in zip(fins, fins[1:])] + [(fins[-1] - 0.1, BACK + 0.05)]
        for (z1, z0) in bays:
            s += tiles(M, x_wall, inward, z0, z1, lambda z: line(z) + 1.07, 11.7, 1.3)
            if z1 - z0 > 2.0:
                zc = (z0 + z1) / 2
                xs = x_wall + inward * 0.05
                s.append(box("speaker", (min(xs, xs + inward * 0.3), 9.6, zc - 0.28), (max(xs, xs + inward * 0.3), 10.4, zc + 0.28), M["speaker"], bevel=0.03, segments=2))
        # Above the panels, a cove ledge with its light hidden on top, washing the wall and ceiling.
        s.append(box("cove", (min(x_wall, x_wall + inward * 0.4), 11.95, BACK), (max(x_wall, x_wall + inward * 0.4), 12.05, PROSCENIUM), M["walnut"], bevel=0.01, segments=1))
        for z0, z1, y in TIERS:
            mid = (z0 + z1) / 2
            area("cove", (x_wall + inward * 0.25, 12.1, mid), z1 - z0, 520, WARM, aim=(x_wall + inward * 1.5, 14, mid), size_y=0.06)
        # A sconce on each fin: brass, a glowing glass, light washing up and down the wall.
        for zf in fins:
            y = line(zf) + 2.9
            xf = x_wall + inward * 0.2
            s.append(box("sconce", (min(xf, xf + inward * 0.1), y - 0.3, zf - 0.06), (max(xf, xf + inward * 0.1), y + 0.3, zf + 0.06), M["brass"], bevel=0.012, segments=2))
            glows.append(box("sconceglass", (min(xf + inward * 0.1, xf + inward * 0.112), y - 0.24, zf - 0.045), (max(xf + inward * 0.1, xf + inward * 0.112), y + 0.24, zf + 0.045), M["sconce"]))
            spot("sconce_up", (xf + inward * 0.15, y + 0.32, zf), (x_wall + inward * 0.05, y + 3.0, zf), 120, 80, 0.6, WARM, radius=0.04)
            spot("sconce_down", (xf + inward * 0.15, y - 0.32, zf), (x_wall + inward * 0.05, y - 3.0, zf), 80, 80, 0.6, WARM, radius=0.04)
            point("sconce_glow", (xf + inward * 0.2, y, zf), 14, SOFT, radius=0.05)
        # A brass handrail along the wall over the stairs, on brackets.
        xr = x_wall + inward * 0.16
        rail = [(FLIGHT_FOOT, line(FLIGHT_FOOT - 0.01) + 0.9), (PARAPET_Z, FIRST_FLOOR + 0.9), (back_edge(ROWS - 1), floor_of(ROWS - 1) + 0.9)]
        for (za, ya), (zb, yb) in zip(rail, rail[1:]):
            s.append(rod("rail", (xr, ya, za), (xr, yb, zb), 0.025, M["brass"]))
            n = max(1, int(abs(zb - za) / 2.2))
            for i in range(n + 1):
                t = i / n
                zz, yy = za + (zb - za) * t, ya + (yb - ya) * t
                s.append(rod("bracket", (x_wall, yy - 0.05, zz), (xr, yy - 0.01, zz), 0.012, M["brass"], sides=6))
        # The exit door beside the stage, in the proscenium wall, its sign lit above.
        dx0, dx1 = sorted((side * 11.5, side * 12.55))
        hall.append(back_panel("door", PROSCENIUM, -1, [(dx0, 0.0), (dx0, 2.25), (dx1, 2.25), (dx1, 0.0)], 0.05, M["walnut"], bevel=0.01, segments=1))
        hall.append(box("doorsplit", ((dx0 + dx1) / 2 - 0.006, 0.02, PROSCENIUM - 0.056), ((dx0 + dx1) / 2 + 0.006, 2.2, PROSCENIUM - 0.05), M["velour"]))
        glows.append(box("exit", (dx0 + 0.2, 2.42, PROSCENIUM - 0.1), (dx1 - 0.2, 2.68, PROSCENIUM - 0.05), M["exit"]))
        point("exit", ((dx0 + dx1) / 2, 2.55, PROSCENIUM - 0.3), 3, (0.2, 1.0, 0.45), radius=0.1)
        # And at the back, a door from the top cross-aisle.
        bx0, bx1 = sorted((side * 10.7, side * 12.1))
        yb = floor_of(ROWS - 1)
        hall.append(back_panel("backdoor", BACK, 1, [(bx0, yb), (bx0, yb + 2.25), (bx1, yb + 2.25), (bx1, yb)], 0.05, M["walnut"], bevel=0.01, segments=1))
        glows.append(box("exit", (bx0 + 0.3, yb + 2.42, BACK + 0.05), (bx1 - 0.3, yb + 2.68, BACK + 0.1), M["exit"]))
        point("exit", ((bx0 + bx1) / 2, yb + 2.55, BACK + 0.3), 3, (0.2, 1.0, 0.45), radius=0.1)
        # Lights over the aisle, down the stairs.
        z = FLIGHT_FOOT - 0.6
        while z > BACK + 0.8:
            yc = ceiling_at(z)
            glows.append(cylinder("downlight", side * 11.9, z, 0.07, yc - 0.012, yc - 0.004, M["down"], segments=16))
            hall.append(cylinder("can", side * 11.9, z, 0.1, yc - 0.01, yc + 0.02, M["velour"], segments=16))
            spot("aisle", (side * 11.9, yc - 0.05, z), (side * 11.9, line(z), z), 45, 45, 0.7, SOFT, radius=0.05)
            z -= 2.4

    # The back wall: walnut below, panels above, the projection booth's two windows.
    yb = floor_of(ROWS - 1)
    hall.append(back_panel("backwall", BACK - 0.1, 1, [(-HALF, yb - 0.3), (-HALF, TIERS[-1][2] + 0.2), (HALF, TIERS[-1][2] + 0.2), (HALF, yb - 0.3)], 0.1, M["wall"]))
    xs = [-HALF + 1.6 * i for i in range(17)] + [HALF]
    for a, b in zip(xs, xs[1:]):
        if b - a < 0.2: continue
        hall.append(back_panel("backwainscot", BACK, 1, [(a + 0.005, yb - 0.1), (a + 0.005, yb + 1.0), (b - 0.005, yb + 1.0), (b - 0.005, yb - 0.1)], 0.03, M["walnut"], bevel=0.006, segments=1))
    hall.append(box("backcap", (-HALF, yb + 1.0, BACK), (HALF, yb + 1.07, BACK + 0.06), M["walnut"], bevel=0.012, segments=2))
    bay_x = [-HALF + 0.1] + [-9.6 + 3.2 * i for i in range(7)] + [HALF - 0.1]
    for a, b in zip(bay_x, bay_x[1:]):
        y = 11.7
        while y - 1.3 > yb + 1.2:
            hall.append(back_panel("backtile", BACK, 1, [(a + 0.06, y - 1.3 + 0.025), (a + 0.06, y - 0.025), (b - 0.06, y - 0.025), (b - 0.06, y - 1.3 + 0.025)], 0.05, M["fabric"], bevel=0.012, segments=2))
            y -= 1.3
        if y - (yb + 1.12) > 0.1:
            hall.append(back_panel("backtile", BACK, 1, [(a + 0.06, yb + 1.12), (a + 0.06, y - 0.025), (b - 0.06, y - 0.025), (b - 0.06, yb + 1.12)], 0.05, M["fabric"], bevel=0.012, segments=2))
    for xc in (-1.1, 1.1):
        hall.append(back_panel("boothframe", BACK + 0.05, 1, [(xc - 0.5, 8.9), (xc - 0.5, 9.75), (xc + 0.5, 9.75), (xc + 0.5, 8.9)], 0.06, M["walnut"], bevel=0.01, segments=1))
        glows.append(back_panel("boothglass", BACK + 0.11, 1, [(xc - 0.4, 9.0), (xc - 0.4, 9.65), (xc + 0.4, 9.65), (xc + 0.4, 9.0)], 0.005, M["booth"]))
        area("booth", (xc, 9.3, BACK + 0.3), 0.8, 40, (1.0, 0.85, 0.65), aim=(xc, 8.5, BACK + 3), size_y=0.6)

    # The ceiling: three steps, each with its cove of light washing the higher one ahead; downlights over the seats.
    for i, (z0, z1, y) in enumerate(TIERS):
        hall.append(box("ceiling", (-HALF - 0.1, y, z0 - (0.05 if i == len(TIERS) - 1 else 0)), (HALF + 0.1, y + 0.2, z1), M["ceiling"]))
        if i > 0:
            y_hi = TIERS[i - 1][2]
            hall.append(box("fascia", (-HALF, y, z1 - 0.02), (HALF, y_hi + 0.2, z1 + 0.02), M["ceiling"]))
            hall.append(box("lip", (-HALF, y - 0.28, z1 - 0.12), (HALF, y + 0.01, z1 + 0.02), M["walnut"], bevel=0.015, segments=2))
            area("tiercove", (0, y + 0.06, z1 + 0.12), 2 * HALF - 0.4, 1600, WARM, aim=(0, y + 3, z1 + 1.8), size_y=0.08)
        z = z1 - 1.6
        while z > z0 + 0.5:
            for x in (-8.4, -4.2, 0.0, 4.2, 8.4):
                glows.append(cylinder("downlight", x, z, 0.075, y - 0.012, y - 0.004, M["down"], segments=16))
                hall.append(cylinder("can", x, z, 0.11, y - 0.01, y + 0.02, M["velour"], segments=16))
                spot("down", (x, y - 0.06, z), (x, 0, z), 70, 55, 0.6, SOFT, radius=0.06)
            z -= 3.4

    # The stage, walnut-fronted, its footlights warm along the lip.
    hall.append(box("stage", (-STAGE_HALF, 0.0, STAGE_FRONT), (STAGE_HALF, STAGE_TOP, 0.3), M["stage"]))
    n = 14
    for i in range(n):
        a = -STAGE_HALF + 2 * STAGE_HALF * i / n
        b = -STAGE_HALF + 2 * STAGE_HALF * (i + 1) / n
        hall.append(box("stagepanel", (a + 0.012, 0.1, STAGE_FRONT - 0.03), (b - 0.012, STAGE_TOP - 0.06, STAGE_FRONT), M["walnut"], bevel=0.008, segments=1))
    hall.append(box("stagelip", (-STAGE_HALF - 0.02, STAGE_TOP - 0.06, STAGE_FRONT - 0.05), (STAGE_HALF + 0.02, STAGE_TOP + 0.02, STAGE_FRONT + 0.06), M["walnut"], bevel=0.02, segments=2))
    hall.append(box("trough", (-STAGE_HALF + 0.3, STAGE_TOP, STAGE_FRONT + 0.08), (STAGE_HALF - 0.3, STAGE_TOP + 0.05, STAGE_FRONT + 0.2), M["velour"]))
    glows.append(box("footlight", (-STAGE_HALF + 0.35, STAGE_TOP + 0.03, STAGE_FRONT + 0.16), (STAGE_HALF - 0.35, STAGE_TOP + 0.051, STAGE_FRONT + 0.19), M["foot"]))
    for i in range(12):
        x = -10.0 + 20.0 * i / 11
        spot("foot", (x, STAGE_TOP + 0.08, STAGE_FRONT + 0.15), (x * 1.05, 8.0, CURTAIN_Z), 110, 50, 0.8, (1.0, 0.66, 0.36), radius=0.08)

    # The proscenium: its wall, a brass moulding round the opening, black reveals and masking round the screen.
    hall.append(box("header", (-HALF, OPENING_TOP, PROSCENIUM), (HALF, TIERS[0][2] + 0.2, PROSCENIUM + 0.3), M["wall"]))
    for side in (1, -1):
        x0, x1 = sorted((side * STAGE_HALF, side * HALF))
        hall.append(box("pillar", (x0, 0.0, PROSCENIUM), (x1, OPENING_TOP, PROSCENIUM + 0.3), M["wall"]))
        xm0, xm1 = sorted((side * STAGE_HALF, side * (STAGE_HALF + 0.16)))
        hall.append(box("moulding", (xm0, STAGE_TOP, PROSCENIUM - 0.08), (xm1, OPENING_TOP + 0.16, PROSCENIUM), M["brass"], bevel=0.02, segments=2))
        xr0, xr1 = sorted((side * (STAGE_HALF - 0.02), side * STAGE_HALF))
        hall.append(box("reveal", (xr0, STAGE_TOP, PROSCENIUM), (xr1, OPENING_TOP, 0.1), M["velour"]))
        xk0, xk1 = sorted((side * SCREEN_W / 2, side * STAGE_HALF))
        hall.append(box("masking", (xk0, STAGE_TOP, 0.03), (xk1, OPENING_TOP, 0.12), M["velour"]))
    hall.append(box("moulding", (-STAGE_HALF - 0.16, OPENING_TOP, PROSCENIUM - 0.08), (STAGE_HALF + 0.16, OPENING_TOP + 0.16, PROSCENIUM), M["brass"], bevel=0.02, segments=2))
    hall.append(box("masking", (-SCREEN_W / 2, SCREEN_BOTTOM + SCREEN_H, 0.03), (SCREEN_W / 2, OPENING_TOP, 0.12), M["velour"]))
    hall.append(box("masking", (-SCREEN_W / 2, STAGE_TOP, 0.03), (SCREEN_W / 2, SCREEN_BOTTOM, 0.12), M["velour"]))
    hall.append(box("teaser", (-STAGE_HALF, OPENING_TOP, -0.3), (STAGE_HALF, OPENING_TOP + 0.02, 0.12), M["velour"]))
    glows.append(box("screen", (-SCREEN_W / 2, SCREEN_BOTTOM, 0.04), (SCREEN_W / 2, SCREEN_BOTTOM + SCREEN_H, 0.1), M["screen"]))
    # The picture's own light on the hall: a soft cool glow from the screen, as from a title waiting.
    area("screenglow", (0, SCREEN_MID, -0.2), SCREEN_W, 600, (0.82, 0.88, 1.0), aim=(0, SCREEN_MID - 2, -10), size_y=SCREEN_H)
    # Velvet drapes either side, and a pleated valance with a gold fringe across the top.
    for side in (1, -1):
        x0, x1 = sorted((side * 10.4, side * 11.4))
        hall.append(pleated("drape", x0, x1, STAGE_TOP, TIERS[0][2], -1.0, 0.22, 5, M["drape"], steps=10, rows=10, sway=0.25))
    hall.append(pleated("valance", -HALF, HALF, 12.72, TIERS[0][2], -1.2, 0.14, 34, M["drape"], steps=8, rows=4))
    hall.append(box("fringe", (-HALF, 12.6, -1.33), (HALF, 12.74, -1.2), M["fringe"], bevel=0.01, segments=1))

    # The front curtain, drawn: velvet in deep folds with a gold fringe, its own model (it rises to open).
    curtain.append(pleated("curtain", -STAGE_HALF - 0.2, STAGE_HALF + 0.2, STAGE_TOP + 0.08, 13.7, CURTAIN_Z, 0.2, 40, M["drape"], steps=8, rows=12, sway=0.15))
    curtain.append(box("curtainfringe", (-STAGE_HALF - 0.2, STAGE_TOP + 0.02, CURTAIN_Z - 0.26), (STAGE_HALF + 0.2, STAGE_TOP + 0.14, CURTAIN_Z - 0.04), M["fringe"], bevel=0.01, segments=1))

    return hall, rows, sides, glows, curtain


def layout(materials_out):
    return {
        "screen": {"width": SCREEN_W, "height": SCREEN_H, "bottom": SCREEN_BOTTOM, "z": 0.0},
        "rows": {"count": ROWS, "nearest": NEAREST, "pitch": PITCH, "firstFloor": FIRST_FLOOR, "rake": RAKE},
        "seatRows": SEAT_ROWS,
        "seatEye": EYE,
        "seatTop": SEAT_TOP, "seatTopBehindEye": SEAT_TOP_BEHIND_EYE,
        "parapet": {"z": PARAPET_Z, "top": PARAPET_H, "depth": 0.18},
        "curtain": {"rise": CURTAIN_RISE, "bottom": STAGE_TOP + 0.02, "top": 13.7, "z": CURTAIN_Z, "front": CURTAIN_Z - 0.26, "halfWidth": STAGE_HALF + 0.2},
        "hall": {"halfWidth": HALF, "back": BACK, "proscenium": PROSCENIUM, "openingTop": OPENING_TOP, "valanceBottom": 12.6},
        "materials": materials_out,
    }


def seat_view(k, look=(0, None, 0)):
    eye = (0.0, floor_of(k) + EYE, eye_z(k))
    aim = (look[0], SCREEN_MID - 1.0 if look[1] is None else look[1], look[2])
    return eye, aim


def main(name="cinema", restyle=None, extra=None):
    """[restyle](M) recolours the materials and [extra](M, hall, glows) adds to the hall: another hall on these rows (palace.py)."""
    mode = sys.argv[-2]
    out = os.path.abspath(sys.argv[-1])
    os.makedirs(out, exist_ok=True)
    reset(16 if QUICK else 64)
    s = bpy.context.scene
    s.cycles.max_bounces = 4
    s.cycles.diffuse_bounces = 3
    s.cycles.glossy_bounces = 0 if mode == "bake" else 1
    s.cycles.transmission_bounces = 0
    s.cycles.transparent_max_bounces = 2
    s.cycles.sample_clamp_indirect = 4.0
    s.cycles.use_light_tree = True
    s.render.threads_mode = "AUTO"
    M = materials()
    if restyle: restyle(M)
    hall, rows, sides, glows, curtain = build(M)
    if extra: extra(M, hall, glows)
    front, _ = seats(M, range(0, 6), "seats_front")
    back, _ = seats(M, range(6, ROWS), "seats_back")
    groups = {
        "hall": join(hall, "hall"),
        "rows": join(rows, "rows"),
        "walls@L": join(sides[1], "walls@L"),
        "walls@R": join(sides[-1], "walls@R"),
        "seats_front": front,
        "seats_back": back,
        "curtain": join(curtain, "curtain"),
    }
    glow_obj = join(glows, "lights")
    log("triangles", {k: triangles([o]) for k, o in groups.items()}, "glows", triangles([glow_obj]))
    exposure = float(os.environ.get("EXPOSURE", "2.0"))
    s.view_settings.exposure = math.log2(exposure)

    if mode == "preview":
        views = os.environ.get("VIEWS")
        if views:
            groups["curtain"].hide_render = True
            for v in views.split(","):
                k, _, look = v.partition("_")
                at, aim = seat_view(int(k[3:]))
                aim = {"": aim, "left": (12, at[1] - 0.5, at[2] + 1.5), "back": (0, at[1] + 0.5, -40), "down": (0, at[1] - 1.6, at[2] + 2.5),
                       "up": (0, at[1] + 6, at[2] + 4)}[look]
                preview(at, aim, os.path.join(out, v + ".png"), res=RES, samples=24 if QUICK else 64, lens=15)
            return
        groups["curtain"].hide_render = True
        for i, k in enumerate(SEAT_ROWS):
            at, aim = seat_view(k)
            preview(at, aim, os.path.join(out, "row%02d.png" % k), res=RES, samples=24 if QUICK else 64, lens=15)
        at, aim = seat_view(4)
        preview(at, (12, at[1] - 0.5, at[2] + 1.5), os.path.join(out, "row04_left.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        preview(at, (0, at[1] + 0.5, -40), os.path.join(out, "row04_back.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        preview(at, (0, at[1] - 1.6, at[2] + 2.5), os.path.join(out, "row04_down.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        groups["curtain"].hide_render = False
        preview(at, aim, os.path.join(out, "row04_curtain.png"), res=RES, samples=24 if QUICK else 64, lens=15)
        return

    # Where anyone could be looking from: the five seats, sitting or standing, leaning, a step or two aside.
    eyes = [Vector(P(dx, floor_of(k) + h, eye_z(k) + dz)) for k in SEAT_ROWS for dx in (-3, -1.5, 0, 1.5, 3)
            for h in (1.0, 1.75) for dz in (-0.4, 0, 0.4)]
    occluders = scene_bvh([o for n, o in groups.items() if n != "curtain"] + [glow_obj])
    # Bake: every atlas first, while the hall is still lit as modelled; the curtain is drawn only for its own.
    sizes = {"hall": 4096, "rows": 2048, "walls@L": 2048, "walls@R": 2048, "seats_front": 4096, "seats_back": 4096, "curtain": 2048}
    if QUICK: sizes = {k: v // 4 for k, v in sizes.items()}
    only = os.environ.get("ONLY")
    raw = {}
    for g, o in groups.items():
        if only and g not in only.split(","): continue
        groups["curtain"].hide_render = g != "curtain"
        raw[g] = bake(o, sizes[g], samples=16 if QUICK else 80, eyes=eyes, scene_bvh=occluders)
        np.save(os.path.join(out, g.replace("@", "_") + ".npy"), raw[g])
    groups["curtain"].hide_render = False
    for g, px in raw.items():
        finish(groups[g], px, out, exposure)
    # Out: the hall and its lights in one model, the curtain in another; and what the headset needs to know.
    hall_objs = [groups[k] for k in ("hall", "rows", "walls@L", "walls@R", "seats_front", "seats_back")] + [glow_obj]
    export(hall_objs, os.path.join(out, name + ".glb"), quality=86)
    export([groups["curtain"]], os.path.join(out, name + "_curtain.glb"), quality=86)
    names = sorted({m.name for o in hall_objs for m in o.data.materials})
    with open(os.path.join(out, name + ".json"), "w") as f:
        json.dump(layout(names), f, indent=1)
    # How it looks baked, as the headset will draw it: nothing lit but what was baked.
    for o in bpy.data.objects:
        if o.type == 'LIGHT': o.hide_render = True
    s.cycles.max_bounces = 0
    groups["curtain"].hide_render = True
    for k in (4, 0, 11):
        at, aim = seat_view(k)
        preview(at, aim, os.path.join(out, "baked_row%02d.png" % k), res=RES, samples=8, lens=15)
    at, aim = seat_view(4)
    preview(at, (12, at[1] - 0.5, at[2] + 1.5), os.path.join(out, "baked_row04_left.png"), res=RES, samples=8, lens=15)
    preview(at, (0, at[1] - 1.6, at[2] + 2.5), os.path.join(out, "baked_row04_down.png"), res=RES, samples=8, lens=15)


if __name__ == "__main__":
    main()
