"""Lumiere's environment kit: the places round you, made as a game's are.

Each place is modelled here in Blender (bpy, run headless), lit with real
lights, and its light baked into textures with Cycles — soft shadows, light
pooling under lamps, the bounce off a wall — then exported as glTF for the
Quest, which draws it unlit and cheaply, dimming it for a film by its
materials' colour (BakedPlace on the headset).

Coordinates are given in the seat's frame the app uses: x to your LEFT, y
UP, z AHEAD toward the screen (P). The glTF exporter's Y-up conversion turns
Blender's (x, y, z) into glTF's (x, z, -y), so P(x, y, z) is Blender's
(x, -z, y).

A material whose name begins "glow" isn't baked: it's exported unlit at its
own colour (a lamp's shade, a sign) and the headset keeps it bright. One
whose name ends "@L" or "@R" lies on that side of you, for the picture's
left or right light.
"""
import bpy
import bmesh
import math
import os
import time
import json
import numpy as np

T0 = time.time()


def log(*a):
    print("[%6.1fs]" % (time.time() - T0), *a, flush=True)


def P(x, y, z):
    """The seat frame (x left, y up, z ahead) to Blender's."""
    return (x, -z, y)


def reset(samples=64):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = 'CYCLES'
    s.cycles.device = 'CPU'
    s.cycles.samples = samples
    s.cycles.use_denoising = False
    s.render.bake.margin = 6
    s.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new("world")
    s.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    return s


# --- Materials ---------------------------------------------------------------------------

def material(name, color, rough=0.7, sheen=0.0, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if sheen:
        b.inputs["Sheen Weight"].default_value = sheen
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def textured(name, color_a, color_b, kind, scale=1.0, rough=0.7, sheen=0.0, bump=0.0):
    """A material whose colour varies between [color_a] and [color_b] by a procedural pattern, in object space."""
    m = material(name, color_a, rough, sheen)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*color_a, 1)
    ramp.color_ramp.elements[1].color = (*color_b, 1)
    if kind == "wood":
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = 'BANDS'; wave.bands_direction = 'X'
        wave.inputs["Scale"].default_value = 3.0
        wave.inputs["Distortion"].default_value = 6.0
        wave.inputs["Detail"].default_value = 3.0
        nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
        nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
        src = wave.outputs["Fac"]
    elif kind == "carpet":
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 9.0
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 60.0
        mix = nt.nodes.new("ShaderNodeMath"); mix.operation = 'ADD'
        nt.links.new(mapping.outputs["Vector"], vor.inputs["Vector"])
        nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 0.35
        nt.links.new(noise.outputs["Fac"], mul.inputs[0])
        nt.links.new(vor.outputs["Distance"], mix.inputs[0]); nt.links.new(mul.outputs[0], mix.inputs[1])
        nt.links.new(mix.outputs[0], ramp.inputs["Fac"])
        src = mix.outputs[0]
    else:  # cloth / plaster: fine noise
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 40.0
        noise.inputs["Detail"].default_value = 8.0
        nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        src = noise.outputs["Fac"]
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    if bump:
        bn = nt.nodes.new("ShaderNodeBump"); bn.inputs["Strength"].default_value = bump
        nt.links.new(src, bn.inputs["Height"]); nt.links.new(bn.outputs["Normal"], b.inputs["Normal"])
    return m


def flat(name, color):
    """A surface shown at its own colour, unlit: Cycles has it glow, and the glTF exporter writes it as
    KHR_materials_unlit at that colour (a colour straight into the surface)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for x in list(nt.nodes):
        if x.type != 'OUTPUT_MATERIAL': nt.nodes.remove(x)
    rgb = nt.nodes.new('ShaderNodeRGB'); rgb.outputs[0].default_value = (*color, 1)
    nt.links.new(rgb.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def glow(name, color):
    """Something that stays lit whatever the house lights do: an exit sign, a step light. Unbaked."""
    return flat("glow:" + name, color)


def lamp(name, color):
    """A house light's own face: a sconce's glass, a downlight. Unbaked, and dimmed with the house lights."""
    return flat("lamp:" + name, color)


# --- Shapes ------------------------------------------------------------------------------

def _finish(o, mat, bevel, segments, smooth):
    if bevel > 0:
        m = o.modifiers.new("bevel", 'BEVEL')
        m.width = bevel; m.segments = segments; m.limit_method = 'ANGLE'
        m.harden_normals = False
    if mat is not None:
        o.data.materials.append(mat)
    if smooth:
        for p in o.data.polygons: p.use_smooth = True
    return o


def box(name, lo, hi, mat=None, bevel=0.0, segments=2, smooth=True):
    """A box between corners [lo] and [hi] in the seat frame (x, y, z), bevelled."""
    cx, cy, cz = [(a + b) / 2 for a, b in zip(lo, hi)]
    sx, sy, sz = [abs(b - a) for a, b in zip(lo, hi)]
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
    bmesh.ops.translate(bm, vec=P(cx, cy, cz), verts=bm.verts)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return _finish(o, mat, bevel, segments, smooth and bevel > 0)


def cylinder(name, x, z, r, y0, y1, mat=None, segments=24, cap=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=segments, radius1=r, radius2=r, depth=y1 - y0)
    bmesh.ops.translate(bm, vec=P(x, (y0 + y1) / 2, z), verts=bm.verts)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return _finish(o, mat, 0, 0, True)


def pleated(name, x0, x1, y0, y1, z, depth, folds, mat=None, steps=8, rows=6, sway=0.0):
    """A curtain hanging in [folds] folds in front of z (toward you), a little fuller at its foot by [sway]."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    n = folds * steps
    grid = []
    for j in range(rows + 1):
        y = y0 + (y1 - y0) * j / rows
        k = 1.0 + sway * (1 - j / rows)
        row = []
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            dz = depth * k * 0.5 * (1 - math.cos(2 * math.pi * folds * i / n))
            row.append(bm.verts.new(P(x, y, z - dz)))
        grid.append(row)
    for j in range(rows):
        for i in range(n):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    sol = o.modifiers.new("thick", 'SOLIDIFY'); sol.thickness = 0.02
    return _finish(o, mat, 0, 0, True)


def _mesh_object(name, bm, mat, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    if mat is not None: o.data.materials.append(mat)
    if smooth:
        for p in o.data.polygons: p.use_smooth = True
    return o


def profile(name, x0, x1, pts, mat=None, caps=True, floor=-1.0):
    """A stepped surface — a flight of stairs, a hall's risers and rows — from its profile [pts], (z, y)
    pairs from front to back, run across from [x0] to [x1]; [caps] closes its ends down to [floor].
    Faces look up and toward the screen, the way the steps are seen."""
    bm = bmesh.new()
    a = [bm.verts.new(P(x0, y, z)) for z, y in pts]
    b = [bm.verts.new(P(x1, y, z)) for z, y in pts]
    for i in range(len(pts) - 1):
        f = bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))
        f.normal_update()
        # Up, or toward the screen (Blender's -y is the seat frame's +z).
        if f.normal.z + (-f.normal.y) < 0: f.normal_flip()
    if caps:
        for side, ring, x in ((-1, a, x0), (1, b, x1)):
            low = [bm.verts.new(P(x, floor, pts[-1][0])), bm.verts.new(P(x, floor, pts[0][0]))]
            f = bm.faces.new(ring + low)
            f.normal_update()
            # Out of the run, away from its middle.
            out = 1 if x == max(x0, x1) else -1
            if f.normal.x * out < 0: f.normal_flip()
    return _mesh_object(name, bm, mat)


def panel(name, x, inward, corners, depth, mat=None, bevel=0.0, segments=2):
    """A panel on the side wall at [x]: [corners] (z, y) round its face, standing [depth] off the wall
    toward the hall ([inward] is -1 for the left wall at +x, +1 for the right)."""
    bm = bmesh.new()
    back = [bm.verts.new(P(x, y, z)) for z, y in corners]
    front = [bm.verts.new(P(x + inward * depth, y, z)) for z, y in corners]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(corners)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _mesh_object(name, bm, mat)
    return _finish(o, None, bevel, segments, bevel > 0)


def back_panel(name, z, outward, corners, depth, mat=None, bevel=0.0, segments=2):
    """A panel on a cross wall at [z] (the back wall), [corners] (x, y), standing [depth] off it toward the
    screen ([outward] +1)."""
    bm = bmesh.new()
    back = [bm.verts.new(P(x, y, z)) for x, y in corners]
    front = [bm.verts.new(P(x, y, z + outward * depth)) for x, y in corners]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(corners)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _mesh_object(name, bm, mat)
    return _finish(o, None, bevel, segments, bevel > 0)


def unwrap_unit(obj, margin=0.01):
    """[obj]'s own atlas layout in the unit square ("bake"), packed tight: a template whose copies each
    take a cell of the atlas (copies with a grid)."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="bake")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=margin, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def tilt(o, degrees, pivot):
    """[o] leaned back by [degrees] (its top away from the screen) about the line across through [pivot]
    (y, z in the seat frame), and the turn applied to its mesh."""
    from mathutils import Matrix, Vector
    piv = Vector(P(0, pivot[0], pivot[1]))
    m = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(-degrees), 4, 'X') @ Matrix.Translation(-piv)
    o.data.transform(m)
    return o


def copies(template, places, name, grid=None, first_cell=0):
    """[template]'s mesh at each of [places] (x, y, z), as one object. With a [grid] (cells a side), the
    template's own atlas layout (unwrap_unit) goes into a cell of its own for each copy, from [first_cell]
    on, so every copy gets the same share of the atlas, packed once."""
    from mathutils import Matrix
    bm = bmesh.new()
    src = template.data
    for i, (x, y, z) in enumerate(places):
        tmp = src.copy()
        tmp.transform(Matrix.Translation(P(x, y, z)))
        if grid and "bake" in tmp.uv_layers:
            uv = tmp.uv_layers["bake"]
            a = np.empty(len(uv.data) * 2, np.float32)
            uv.data.foreach_get("uv", a)
            a = a.reshape(-1, 2)
            c = first_cell + i
            col, row = c % grid, c // grid
            pad = 0.012
            a[:, 0] = (col + pad + a[:, 0] * (1 - 2 * pad)) / grid
            a[:, 1] = (row + pad + a[:, 1] * (1 - 2 * pad)) / grid
            uv.data.foreach_set("uv", a.ravel())
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    o = _mesh_object(name, bm, None)
    for m in src.materials: o.data.materials.append(m)
    return o


def apply_all(objs):
    for o in objs:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                log("modifier", m.name, "on", o.name, "failed:", e)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    apply_all(objs)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def triangles(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        if o.type == 'MESH':
            e = o.evaluated_get(dg)
            n += sum(len(p.vertices) - 2 for p in e.data.polygons)
    return n


# --- Lights ------------------------------------------------------------------------------

def area(name, at, size, power, color=(1, 0.85, 0.7), aim=None, shape='RECTANGLE', size_y=None):
    l = bpy.data.lights.new(name, 'AREA')
    l.energy = power; l.color = color; l.shape = shape; l.size = size
    if size_y: l.size_y = size_y
    o = bpy.data.objects.new(name, l)
    o.location = P(*at)
    bpy.context.collection.objects.link(o)
    if aim:
        d = np.array(P(*aim)) - np.array(P(*at))
        o.rotation_mode = 'QUATERNION'
        from mathutils import Vector
        o.rotation_quaternion = Vector(d).to_track_quat('-Z', 'Y')
    return o


def point(name, at, power, color=(1, 0.8, 0.6), radius=0.05):
    l = bpy.data.lights.new(name, 'POINT')
    l.energy = power; l.color = color; l.shadow_soft_size = radius
    o = bpy.data.objects.new(name, l)
    o.location = P(*at)
    bpy.context.collection.objects.link(o)
    return o


def spot(name, at, aim, power, angle_deg=60, blend=0.5, color=(1, 0.85, 0.7), radius=0.05):
    l = bpy.data.lights.new(name, 'SPOT')
    l.energy = power; l.color = color; l.spot_size = math.radians(angle_deg); l.spot_blend = blend
    l.shadow_soft_size = radius
    o = bpy.data.objects.new(name, l)
    o.location = P(*at)
    bpy.context.collection.objects.link(o)
    from mathutils import Vector
    d = Vector(P(*aim)) - Vector(P(*at))
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('-Z', 'Y')
    return o


# --- Baking ------------------------------------------------------------------------------

def bake(obj, size, samples=64, margin=4, eyes=None, scene_bvh=None):
    """[obj]'s diffuse light and colour, baked into a fresh atlas of its own: linear floats, [size] square,
    with a mask of what was baked. The object keeps its materials until [finish]. Laid out afresh unless it
    has its layout already ("bake", from copies with a grid); given [eyes] and the scene ([scene_bvh]), the
    parts never seen from any of them take a sliver of the atlas, so what is seen takes the rest."""
    s = bpy.context.scene
    s.cycles.samples = samples
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    me = obj.data
    if "bake" not in me.uv_layers:
        while me.uv_layers:
            me.uv_layers.remove(me.uv_layers[0])
        me.uv_layers.new(name="bake")
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=margin / size, area_weight=0.0, scale_to_bounds=True)
        bpy.ops.object.mode_set(mode='OBJECT')
        if eyes and scene_bvh:
            shrink_unseen(obj, eyes, scene_bvh)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.pack_islands(margin=margin / size, rotate=True, scale=True)
        bpy.ops.object.mode_set(mode='OBJECT')
    # A bake that was cut short resumes: atlases already baked (in $RESUME) are read back, not baked again.
    cache = os.path.join(os.environ["RESUME"], obj.name.replace("@", "_") + ".npy") if os.environ.get("RESUME") else None
    if cache and os.path.exists(cache):
        log("resumed", obj.name, "from", cache)
        return np.load(cache)
    img = bpy.data.images.new(obj.name + "_bake", size, size, float_buffer=True, alpha=True)
    img.generated_color = (0, 0, 0, 0)
    nodes = []
    for m in me.materials:
        nt = m.node_tree
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = img
        for x in nt.nodes: x.select = False
        n.select = True; nt.nodes.active = n
        nodes.append((nt, n))
    s.render.bake.use_pass_direct = True
    s.render.bake.use_pass_indirect = True
    s.render.bake.use_pass_color = True
    s.render.bake.margin = margin
    s.render.bake.target = 'IMAGE_TEXTURES'
    t = time.time()
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'DIRECT', 'INDIRECT', 'COLOR'}, margin=margin)
    log("baked", obj.name, size, "in %.0fs" % (time.time() - t))
    for nt, n in nodes: nt.nodes.remove(n)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
    bpy.data.images.remove(img)
    if cache: np.save(cache, px)
    return px


def finish(obj, px, out_dir, exposure=1.0, knee=0.62):
    """The bake [px] cleaned of its grain, exposed, rolled off softly toward white rather than clipped,
    saved (sRGB PNG; JPEG once exported), and shown on [obj] as its one unlit material, named
    "<obj>/baked" so the headset knows it (and its side, from an "@L" or "@R" in the name)."""
    size = px.shape[0]
    rgb = denoise(px[..., :3], px[..., 3]) * exposure
    rgb = np.clip(rgb, 0, None)
    over = rgb > knee
    rgb = np.where(over, knee + (1 - knee) * (1 - np.exp(-(rgb - knee) / (1 - knee))), rgb)
    srgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(np.clip(rgb, 1e-8, None), 1 / 2.4) - 0.055)
    path = os.path.join(out_dir, obj.name.replace("@", "_") + ".png")
    out = bpy.data.images.new(obj.name + "_out", size, size)
    out.pixels[:] = np.concatenate([np.clip(srgb, 0, 1), np.ones((size, size, 1), np.float32)], -1).ravel()
    out.filepath_raw = path; out.file_format = 'PNG'; out.save()
    baked = bpy.data.materials.new(obj.name + "/baked")
    baked.use_nodes = True
    nt = baked.node_tree
    for x in list(nt.nodes):
        if x.type != 'OUTPUT_MATERIAL': nt.nodes.remove(x)
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = out
    tex.interpolation = 'Linear'
    nt.links.new(tex.outputs["Color"], nt.nodes["Material Output"].inputs["Surface"])
    obj.data.materials.clear()
    obj.data.materials.append(baked)
    return path


def scene_bvh(objs):
    """Every face of [objs] (their modifiers applied), to see what hides what."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    for o in objs:
        if o.type == 'MESH':
            bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def shrink_unseen(obj, eyes, bvh, keep=0.12):
    """Each island of [obj]'s layout that no face of can be seen from any of [eyes] (its middle facing away,
    or behind something) shrunk to [keep] of its size: the back of a panel against a wall, the top of the
    ceiling, under the stage."""
    from mathutils import Vector
    me = obj.data
    uv = me.uv_layers["bake"].data
    seen = []
    for p in me.polygons:
        n = p.normal
        # Its middle, and points toward each corner: a big face can be hidden in the middle and seen at its ends.
        corners = [me.vertices[v].co for v in p.vertices]
        points = [p.center] + [p.center + (c - p.center) * f for c in corners for f in (0.5, 0.92)]
        vis = False
        for e in eyes:
            for q in points:
                c = q + n * 0.004
                d = c - e
                if n.dot(d) >= 0:
                    break
                dist = d.length
                hit = bvh.ray_cast(e, d / dist, dist - 0.01)
                if hit[0] is None:
                    vis = True
                    break
            if vis:
                break
        seen.append(vis)
    # Islands: faces joined across an edge their UVs share.
    parent = list(range(len(me.polygons)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    edge_faces = {}
    for p in me.polygons:
        for li in p.loop_indices:
            lp = me.loops[li]
            nxt = p.loop_indices[(list(p.loop_indices).index(li) + 1) % p.loop_total]
            key = tuple(sorted((lp.vertex_index, me.loops[nxt].vertex_index)))
            uva, uvb = tuple(uv[li].uv), tuple(uv[nxt].uv)
            edge_faces.setdefault(key, []).append((p.index, {lp.vertex_index: uva, me.loops[nxt].vertex_index: uvb}))
    for key, fs in edge_faces.items():
        for i in range(1, len(fs)):
            (fa, ua), (fb, ub) = fs[0], fs[i]
            if all(abs(ua[v][0] - ub[v][0]) < 1e-6 and abs(ua[v][1] - ub[v][1]) < 1e-6 for v in key):
                ra, rb = find(fa), find(fb)
                if ra != rb: parent[ra] = rb
    islands = {}
    for p in me.polygons:
        islands.setdefault(find(p.index), []).append(p.index)
    shrunk = 0
    for root, faces in islands.items():
        if any(seen[f] for f in faces):
            continue
        loops = [li for f in faces for li in me.polygons[f].loop_indices]
        cu = sum(uv[li].uv[0] for li in loops) / len(loops)
        cv = sum(uv[li].uv[1] for li in loops) / len(loops)
        for li in loops:
            u, v = uv[li].uv
            uv[li].uv = (cu + (u - cu) * keep, cv + (v - cv) * keep)
        shrunk += len(faces)
    log(obj.name, "unseen faces:", shrunk, "of", len(me.polygons), "in", len(islands), "islands")


def side_suffix(name):
    return "@L" if name.endswith("@L") else "@R" if name.endswith("@R") else ""


def denoise(rgb, alpha, steps=(1, 2, 3), sigma=0.18):
    """The sampling's grain smoothed away within what was baked ([alpha] marks it): an edge-stopping
    à-trous filter, a 5x5 B-spline at growing spacings, each neighbour weighed down by how far its
    brightness is from the pixel's own (so a shadow's edge, or a different part of the atlas next door,
    stays out of it)."""
    k = np.array([1 / 16, 1 / 4, 3 / 8, 1 / 4, 1 / 16], np.float32)
    mask = (alpha > 0.5).astype(np.float32)
    out = rgb.astype(np.float32).copy()
    for step in steps:
        lum = out.mean(-1)
        acc = np.zeros_like(out)
        wsum = np.zeros_like(lum)
        for i, ki in enumerate(k):
            dy = (i - 2) * step
            for j, kj in enumerate(k):
                dx = (j - 2) * step
                n = np.roll(out, (dy, dx), (0, 1))
                nl = np.roll(lum, (dy, dx), (0, 1))
                nm = np.roll(mask, (dy, dx), (0, 1))
                w = ki * kj * nm * np.exp(-np.abs(nl - lum) / (sigma * (lum + 0.02)))
                acc += n * w[..., None]
                wsum += w
        out = np.where(mask[..., None] > 0, acc / np.maximum(wsum, 1e-8)[..., None], out)
    return out


def export(objs, path, quality=88):
    """[objs] as one glTF binary, images as JPEG."""
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_image_format='JPEG', export_jpeg_quality=quality, export_yup=True,
                              export_lights=False, export_cameras=False, export_materials='EXPORT')
    log("exported", os.path.basename(path), "%.1f MB" % (os.path.getsize(path) / 1e6))


def preview(at, aim, path, res=(1280, 720), samples=48, lens=18):
    """A Cycles picture from [at] looking at [aim] (seat frame): how the place looks before baking."""
    from mathutils import Vector
    cam = bpy.data.cameras.new("preview"); cam.lens = lens
    o = bpy.data.objects.new("preview", cam)
    bpy.context.collection.objects.link(o)
    o.location = P(*at)
    d = Vector(P(*aim)) - Vector(P(*at))
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('-Z', 'Y')
    s = bpy.context.scene
    s.camera = o
    s.render.resolution_x, s.render.resolution_y = res
    s.cycles.samples = samples
    s.cycles.use_denoising = False
    s.render.filepath = path
    bpy.ops.render.render(write_still=True)
    s.cycles.use_denoising = False
    bpy.data.objects.remove(o)
    log("preview", os.path.basename(path))
