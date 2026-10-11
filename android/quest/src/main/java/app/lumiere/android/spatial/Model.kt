package app.lumiere.android.spatial

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Which way a face looks, for the light it catches. The house lights fall
 * from above, so faces turned up take the most of them and faces turned
 * down the least; the film's light comes from the screen ahead (+Z), so a
 * face turned to the screen takes the most of it, and the backs of the
 * seats before you, turned to you, stand dark against the picture. Shading
 * by facing is what gives a shape its form: without it every side of a box
 * is one flat colour.
 */
enum class Facing(val house: Float, val screen: Float) {
    UP(1f, 0.55f), SCREENWARD(0.74f, 1f), SIDEWAYS(0.82f, 0.6f), VIEWERWARD(0.68f, 0.14f), DOWN(0.5f, 0.3f);

    /** A colour as a face looking this way shows it, with the house lights at [level] (1 up, low in a film). */
    fun shade(c: Triple<Float, Float, Float>, level: Float): Triple<Float, Float, Float> {
        val k = house * level + screen * (1f - level)
        return Triple((c.first * k).coerceIn(0f, 1f), (c.second * k).coerceIn(0f, 1f), (c.third * k).coerceIn(0f, 1f))
    }

    companion object {
        fun of(nx: Float, ny: Float, nz: Float): Facing = when {
            ny > 0.6f -> UP
            ny < -0.6f -> DOWN
            abs(nx) >= abs(nz) -> SIDEWAYS
            nz > 0f -> SCREENWARD
            else -> VIEWERWARD
        }
    }
}

/** Left of you (+X), right of you, or across the middle: which half of the picture's light a part takes. */
enum class Side {
    LEFT, MIDDLE, RIGHT;

    companion object {
        /** By where a part's middle is: more than [SIDE_M] either side of you, it's on that side. */
        fun of(x: Float): Side = when { x > SIDE_M -> LEFT; x < -SIDE_M -> RIGHT; else -> MIDDLE }
        const val SIDE_M = 2.5f
    }
}

/**
 * One mesh's triangles: positions, normals, texture coordinates (in
 * repeats of its texture, so a surface tiles at its real size) and the
 * indices that join them. Grows as shapes are added; read out once.
 */
class MeshData {
    private var p = FloatArray(3 * 256)
    private var n = FloatArray(3 * 256)
    private var t = FloatArray(2 * 256)
    private var ix = IntArray(3 * 256)
    var vertices = 0
        private set
    var indexCount = 0
        private set
    /** The corners of everything in it. */
    val min = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
    val max = floatArrayOf(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)

    fun vertex(x: Float, y: Float, z: Float, nx: Float, ny: Float, nz: Float, u: Float, v: Float): Int {
        if (3 * (vertices + 1) > p.size) {
            p = p.copyOf(p.size * 2); n = n.copyOf(n.size * 2); t = t.copyOf(t.size * 2)
        }
        val i = vertices++
        p[3 * i] = x; p[3 * i + 1] = y; p[3 * i + 2] = z
        n[3 * i] = nx; n[3 * i + 1] = ny; n[3 * i + 2] = nz
        t[2 * i] = u; t[2 * i + 1] = v
        min[0] = min(min[0], x); min[1] = min(min[1], y); min[2] = min(min[2], z)
        max[0] = max(max[0], x); max[1] = max(max[1], y); max[2] = max(max[2], z)
        return i
    }

    fun triangle(a: Int, b: Int, c: Int) {
        if (indexCount + 3 > ix.size) ix = ix.copyOf(ix.size * 2)
        ix[indexCount++] = a; ix[indexCount++] = b; ix[indexCount++] = c
    }

    fun positions(): FloatArray = p.copyOf(3 * vertices)
    fun normals(): FloatArray = n.copyOf(3 * vertices)
    fun uvs(): FloatArray = t.copyOf(2 * vertices)
    fun indices(): IntArray = ix.copyOf(indexCount)
}

/**
 * A place's parts made as real shapes — bevelled cushions, round cup
 * holders, curtains hanging in folds, seat backs tilted as seat backs are —
 * rather than plain boxes, and gathered into one mesh for each kind of
 * part, side of you and way of facing, so a whole hall is a few dozen draw
 * calls however much is in it. [tiles] gives each kind's texture its real
 * size (metres across, metres up), so a carpet's pattern or a velvet's pile
 * keeps its scale on every face. Pure, so it's tested without a headset.
 */
class Modeller<K>(
    private val tiles: (K) -> Pair<Float, Float>? = { null },
    /** Whether a kind takes its light by the way each face looks (not lights, nor what's nearly black). */
    private val shaded: (K) -> Boolean = { true },
    /** Whether a kind takes the light of the side of the picture it's on (what's on the walls). */
    private val sided: (K) -> Boolean = { true },
    /**
     * Five ways of facing, telling the faces turned to the screen from those
     * turned to you (the seats before you dark against the picture); or
     * three — up, sideways, down — for a place of few parts, where each way
     * is another mesh to draw.
     */
    private val fivefold: Boolean = true,
) {
    /** One mesh's worth: a kind of part, on one side of you, facing one way (in [chunk]s, if there's a great deal of it). */
    data class Piece<K>(val kind: K, val side: Side, val facing: Facing, val chunk: Int = 0)

    val meshes = LinkedHashMap<Piece<K>, MeshData>()
    private val chunks = HashMap<Piece<K>, Int>()

    private var kind: K? = null
    private var side = Side.MIDDLE
    private var tileU = 1f
    private var tileV = 1f
    // Where shapes go: world = r · local + o (a turn and a tilt, then a shift).
    private var r = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
    private var o = floatArrayOf(0f, 0f, 0f)

    /** Shapes from here on are [kind], taking the light of the side [x] is on. */
    fun part(kind: K, x: Float): Modeller<K> {
        this.kind = kind
        side = if (sided(kind)) Side.of(x) else Side.MIDDLE
        val tile = tiles(kind)
        // 0 lays the texture once across the face that way (a picture, a row of spines).
        tileU = tile?.first ?: 1f
        tileV = tile?.second ?: 1f
        return this
    }

    /** [shapes] leaning back by [degrees] (their tops away from the screen) about the line across through ([y], [z]). */
    fun tilted(degrees: Float, y: Float, z: Float, shapes: () -> Unit) {
        val a = Math.toRadians(-degrees.toDouble()).toFloat()
        val c = cos(a); val s = sin(a)
        around(floatArrayOf(1f, 0f, 0f, 0f, c, -s, 0f, s, c), 0f, y, z, shapes)
    }

    /** [shapes] turned [degrees] about the upright through ([x], [z]): positive turns what faced the screen (+Z) toward your left (+X). */
    fun turned(degrees: Float, x: Float, z: Float, shapes: () -> Unit) {
        val a = Math.toRadians(degrees.toDouble()).toFloat()
        val c = cos(a); val s = sin(a)
        around(floatArrayOf(c, 0f, s, 0f, 1f, 0f, -s, 0f, c), x, 0f, z, shapes)
    }

    private fun around(rot: FloatArray, px: Float, py: Float, pz: Float, shapes: () -> Unit) {
        val r0 = r; val o0 = o
        // world = r0 · (rot · (local − p) + p) + o0
        val rp = mul(rot, floatArrayOf(px, py, pz))
        val shift = floatArrayOf(px - rp[0], py - rp[1], pz - rp[2])
        r = matMul(r0, rot)
        val s = mul(r0, shift)
        o = floatArrayOf(o0[0] + s[0], o0[1] + s[1], o0[2] + s[2])
        try { shapes() } finally { r = r0; o = o0 }
    }

    /**
     * A flat face through [corners] (x, y, z triples, in order round its
     * edge), seen from outside along [outward] (local), so it's shaded and
     * mapped as it faces once placed.
     */
    fun face(corners: FloatArray, outward: FloatArray) {
        val k = kind ?: return
        val count = corners.size / 3
        if (count < 3) return
        val nw = mul(r, outward).let { normalise(it) }
        val facing = if (!shaded(k)) Facing.SIDEWAYS else Facing.of(nw[0], nw[1], nw[2]).let {
            if (fivefold || it == Facing.UP || it == Facing.DOWN) it else Facing.SIDEWAYS
        }
        // A mesh stays well within what sixteen-bit indices can reach; past that, another of the same.
        val base: Piece<K> = Piece(k, side, facing)
        var piece: Piece<K> = base.copy(chunk = chunks[base] ?: 0)
        if ((meshes[piece]?.vertices ?: 0) + count > MAX_VERTICES) {
            piece = piece.copy(chunk = piece.chunk + 1)
            chunks[base] = piece.chunk
        }
        val mesh = meshes.getOrPut(piece) { MeshData() }
        val first = mesh.vertices
        // The texture runs across the face as you'd read it standing before it, top up: along
        // its right-hand edge and down it; on a floor or a ceiling, across and ahead.
        val flat = abs(nw[1]) >= 0.7071f
        val across = if (flat) floatArrayOf(1f, 0f, 0f) else normalise(floatArrayOf(nw[2], 0f, -nw[0]))
        val down = if (flat) floatArrayOf(0f, 0f, 1f) else floatArrayOf(0f, -1f, 0f)
        val world = FloatArray(3 * count)
        val uv = FloatArray(2 * count)
        for (i in 0 until count) {
            val w = mul(r, floatArrayOf(corners[3 * i], corners[3 * i + 1], corners[3 * i + 2]))
            world[3 * i] = w[0] + o[0]; world[3 * i + 1] = w[1] + o[1]; world[3 * i + 2] = w[2] + o[2]
            uv[2 * i] = dot(world, 3 * i, across); uv[2 * i + 1] = dot(world, 3 * i, down)
        }
        // At its real size, so it tiles at its scale; or once across the face.
        for (axis in 0..1) {
            val tile = if (axis == 0) tileU else tileV
            if (tile > 0f) for (i in 0 until count) uv[2 * i + axis] /= tile
            else {
                var lo = Float.MAX_VALUE; var hi = -Float.MAX_VALUE
                for (i in 0 until count) { lo = min(lo, uv[2 * i + axis]); hi = max(hi, uv[2 * i + axis]) }
                val span = (hi - lo).coerceAtLeast(1e-4f)
                for (i in 0 until count) uv[2 * i + axis] = (uv[2 * i + axis] - lo) / span
            }
        }
        for (i in 0 until count)
            mesh.vertex(world[3 * i], world[3 * i + 1], world[3 * i + 2], nw[0], nw[1], nw[2], uv[2 * i], uv[2 * i + 1])
        for (i in 1 until count - 1) mesh.triangle(first, first + i, first + i + 1)
    }

    /** A plain box between two corners; [skip] leaves out faces nobody sees (e.g. [DOWN_FACE] on the floor). */
    fun box(x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float, skip: Int = 0) {
        if (skip and UP_FACE == 0) face(floatArrayOf(x0, y1, z0, x0, y1, z1, x1, y1, z1, x1, y1, z0), UP_N)
        if (skip and DOWN_FACE == 0) face(floatArrayOf(x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1), DOWN_N)
        if (skip and LEFT_FACE == 0) face(floatArrayOf(x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1), LEFT_N)
        if (skip and RIGHT_FACE == 0) face(floatArrayOf(x0, y0, z0, x0, y0, z1, x0, y1, z1, x0, y1, z0), RIGHT_N)
        if (skip and FRONT_FACE == 0) face(floatArrayOf(x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1), FRONT_N)
        if (skip and BACK_FACE == 0) face(floatArrayOf(x0, y0, z0, x0, y1, z0, x1, y1, z0, x1, y0, z0), BACK_N)
    }

    /** A block's box. */
    fun box(b: Block<*>, skip: Int = 0) = box(b.x - b.w / 2, b.x + b.w / 2, b.bottom, b.top, b.back, b.front, skip)

    /**
     * A box with its edges and corners bevelled by [bevel]: a cushion, an
     * armrest, a moulding — a soft edge catches the light as a sharp one doesn't.
     */
    fun chamfered(x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float, bevel: Float, skip: Int = 0) {
        val b = bevel.coerceAtMost(min(x1 - x0, min(y1 - y0, z1 - z0)) * 0.45f)
        if (b <= 1e-4f) { box(x0, x1, y0, y1, z0, z1, skip); return }
        val xa = x0 + b; val xb = x1 - b; val ya = y0 + b; val yb = y1 - b; val za = z0 + b; val zb = z1 - b
        // The six faces, inset.
        if (skip and UP_FACE == 0) face(floatArrayOf(xa, y1, za, xa, y1, zb, xb, y1, zb, xb, y1, za), UP_N)
        if (skip and DOWN_FACE == 0) face(floatArrayOf(xa, y0, za, xb, y0, za, xb, y0, zb, xa, y0, zb), DOWN_N)
        face(floatArrayOf(x1, ya, za, x1, yb, za, x1, yb, zb, x1, ya, zb), LEFT_N)
        face(floatArrayOf(x0, ya, za, x0, ya, zb, x0, yb, zb, x0, yb, za), RIGHT_N)
        face(floatArrayOf(xa, ya, z1, xb, ya, z1, xb, yb, z1, xa, yb, z1), FRONT_N)
        face(floatArrayOf(xa, ya, z0, xa, yb, z0, xb, yb, z0, xb, ya, z0), BACK_N)
        // The twelve bevels between them.
        val d = 0.7071f
        face(floatArrayOf(xb, y1, za, xb, y1, zb, x1, yb, zb, x1, yb, za), floatArrayOf(d, d, 0f))
        face(floatArrayOf(x0, yb, za, x0, yb, zb, xa, y1, zb, xa, y1, za), floatArrayOf(-d, d, 0f))
        face(floatArrayOf(x1, ya, za, x1, ya, zb, xb, y0, zb, xb, y0, za), floatArrayOf(d, -d, 0f))
        face(floatArrayOf(xa, y0, za, xa, y0, zb, x0, ya, zb, x0, ya, za), floatArrayOf(-d, -d, 0f))
        face(floatArrayOf(xa, y1, zb, xb, y1, zb, xb, yb, z1, xa, yb, z1), floatArrayOf(0f, d, d))
        face(floatArrayOf(xa, yb, z0, xb, yb, z0, xb, y1, za, xa, y1, za), floatArrayOf(0f, d, -d))
        face(floatArrayOf(xa, ya, z1, xb, ya, z1, xb, y0, zb, xa, y0, zb), floatArrayOf(0f, -d, d))
        face(floatArrayOf(xa, y0, za, xb, y0, za, xb, ya, z0, xa, ya, z0), floatArrayOf(0f, -d, -d))
        face(floatArrayOf(xb, ya, z1, xb, yb, z1, x1, yb, zb, x1, ya, zb), floatArrayOf(d, 0f, d))
        face(floatArrayOf(x0, ya, zb, x0, yb, zb, xa, yb, z1, xa, ya, z1), floatArrayOf(-d, 0f, d))
        face(floatArrayOf(x1, ya, za, x1, yb, za, xb, yb, z0, xb, ya, z0), floatArrayOf(d, 0f, -d))
        face(floatArrayOf(xa, ya, z0, xa, yb, z0, x0, yb, za, x0, ya, za), floatArrayOf(-d, 0f, -d))
        // The eight corners.
        val e = 0.577f
        for (sx in 0..1) for (sy in 0..1) for (sz in 0..1) {
            val cx = if (sx == 1) x1 else x0; val ix = if (sx == 1) xb else xa
            val cy = if (sy == 1) y1 else y0; val iy = if (sy == 1) yb else ya
            val cz = if (sz == 1) z1 else z0; val iz = if (sz == 1) zb else za
            face(floatArrayOf(cx, iy, iz, ix, cy, iz, ix, iy, cz),
                floatArrayOf(if (sx == 1) e else -e, if (sy == 1) e else -e, if (sz == 1) e else -e))
        }
    }

    /** An upright cylinder round ([cx], [cz]) of radius [radius], from [y0] to [y1], in [segments] sides, with its top. */
    fun cylinder(cx: Float, cz: Float, radius: Float, y0: Float, y1: Float, segments: Int = 12, top: Boolean = true) {
        for (i in 0 until segments) {
            val a0 = 2 * Math.PI.toFloat() * i / segments; val a1 = 2 * Math.PI.toFloat() * (i + 1) / segments
            val am = (a0 + a1) / 2
            val xa = cx + radius * sin(a0); val za = cz + radius * cos(a0)
            val xb = cx + radius * sin(a1); val zb = cz + radius * cos(a1)
            face(floatArrayOf(xa, y0, za, xb, y0, zb, xb, y1, zb, xa, y1, za), floatArrayOf(sin(am), 0f, cos(am)))
        }
        if (top) {
            val ring = FloatArray(3 * segments)
            for (i in 0 until segments) {
                val a = 2 * Math.PI.toFloat() * i / segments
                ring[3 * i] = cx + radius * sin(a); ring[3 * i + 1] = y1; ring[3 * i + 2] = cz + radius * cos(a)
            }
            face(ring, UP_N)
        }
    }

    /**
     * A curtain hanging in [folds] deep folds from [x0] to [x1] and [y0] to
     * [y1], its folds [depth] deep in front of [z] (toward you, −Z), seen
     * from the hall; its edges closed so it reads as cloth with thickness.
     */
    fun pleats(x0: Float, x1: Float, y0: Float, y1: Float, z: Float, depth: Float, folds: Int, steps: Int = 6) {
        val n = (folds * steps).coerceAtLeast(2)
        val w = x1 - x0
        fun zAt(i: Int) = z - depth * 0.5f * (1f - cos(2 * Math.PI.toFloat() * folds * i / n))
        for (i in 0 until n) {
            val xa = x0 + w * i / n; val xb = x0 + w * (i + 1) / n
            val za = zAt(i); val zb = zAt(i + 1)
            // The outward normal of the cloth between: toward you, leaning as the fold turns.
            val dx = xb - xa; val dz = zb - za
            val len = sqrt(dx * dx + dz * dz)
            face(floatArrayOf(xa, y0, za, xa, y1, za, xb, y1, zb, xb, y0, zb), floatArrayOf(dz / len, 0f, -dx / len))
        }
        // A thin back and edges, so from the side it isn't a ribbon.
        face(floatArrayOf(x0, y0, z + 0.01f, x1, y0, z + 0.01f, x1, y1, z + 0.01f, x0, y1, z + 0.01f), FRONT_N)
        face(floatArrayOf(x0, y0, z + 0.01f, x0, y1, z + 0.01f, x0, y1, zAt(0), x0, y0, zAt(0)), RIGHT_N)
        face(floatArrayOf(x1, y0, z + 0.01f, x1, y0, zAt(n), x1, y1, zAt(n), x1, y1, z + 0.01f), LEFT_N)
    }

    /** A thin frame [width] wide round the rectangle from ([x0], [y0]) to ([x1], [y1]), [depth] proud of the wall at [z], facing −Z. */
    fun frame(x0: Float, x1: Float, y0: Float, y1: Float, z: Float, width: Float, depth: Float) {
        val zf = z - depth
        chamfered(x0 - width, x1 + width, y1, y1 + width, zf, z, width * 0.3f)
        chamfered(x0 - width, x1 + width, y0 - width, y0, zf, z, width * 0.3f)
        chamfered(x0 - width, x0, y0, y1, zf, z, width * 0.3f)
        chamfered(x1, x1 + width, y0, y1, zf, z, width * 0.3f)
    }

    companion object {
        /** The most vertices in one mesh. */
        const val MAX_VERTICES = 60_000
        const val UP_FACE = 1
        const val DOWN_FACE = 2
        const val LEFT_FACE = 4      // +X
        const val RIGHT_FACE = 8     // −X
        const val FRONT_FACE = 16    // +Z, toward the screen
        const val BACK_FACE = 32     // −Z, toward you
        private val UP_N = floatArrayOf(0f, 1f, 0f)
        private val DOWN_N = floatArrayOf(0f, -1f, 0f)
        private val LEFT_N = floatArrayOf(1f, 0f, 0f)
        private val RIGHT_N = floatArrayOf(-1f, 0f, 0f)
        private val FRONT_N = floatArrayOf(0f, 0f, 1f)
        private val BACK_N = floatArrayOf(0f, 0f, -1f)

        private fun mul(m: FloatArray, v: FloatArray) = floatArrayOf(
            m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
            m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
            m[6] * v[0] + m[7] * v[1] + m[8] * v[2])

        private fun matMul(a: FloatArray, b: FloatArray) = FloatArray(9) { i ->
            val row = i / 3; val col = i % 3
            a[3 * row] * b[col] + a[3 * row + 1] * b[3 + col] + a[3 * row + 2] * b[6 + col]
        }

        private fun dot(a: FloatArray, at: Int, b: FloatArray) = a[at] * b[0] + a[at + 1] * b[1] + a[at + 2] * b[2]

        private fun normalise(v: FloatArray): FloatArray {
            val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).coerceAtLeast(1e-6f)
            return floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
        }
    }
}
