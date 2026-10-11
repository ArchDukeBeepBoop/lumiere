package app.lumiere.android.spatial

import android.net.Uri
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * A place's surroundings round your seat — the cinema's hall, the cabin,
 * the lakeside's pontoon, the terrace, the Moon's deck, the station — from
 * its blocks. Each block is made as a real shape by [shape] (a bevelled
 * cushion, a curtain in folds, a seat with its arms; a plain box unless the
 * place models it), and everything that stays still is gathered into one
 * mesh for each kind of part, side of you and way of facing (Modeller), so
 * a whole hall is a few dozen draw calls however much is in it. What
 * [moves] — a flame, a firefly, a curtain drawing back — is a mesh of its
 * own, moved each frame by [animate].
 *
 * Colours are unlit, worked out here from the house lights and the film's
 * colour by [colour], then shaded by which way each face looks (Facing) —
 * except what [glows], which shines at its own colour — and laid over the
 * [surface] it's made of (ModelMeshes.light). Nothing is lit on the headset,
 * and the light changes only when it does. The film's colour comes in two
 * halves: what's on your left takes the picture's left half, and so on.
 */
class Scenery<K>(
    private val colour: (K, Float, Triple<Float, Float, Float>?) -> Triple<Float, Float, Float>,
    private val surface: (K) -> Surface? = { null },
    private val moves: (Block<K>, Int, Float) -> Life.Sway? = { _, _, _ -> null },
    private val glows: (K) -> Boolean = { false },
    private val shape: (Block<K>, Modeller<K>) -> Unit = { b, m -> m.box(b) },
    /** Whether a kind is shaded by the way it faces; by default all but what [glows]. */
    private val shaded: (K) -> Boolean = { !glows(it) },
    /** Whether a kind takes the light of its own side of the picture; by default all. */
    private val sided: (K) -> Boolean = { true },
    /** Five ways of facing (the cinema), or three (Modeller). */
    private val fivefold: Boolean = false,
) {
    /** One mesh on the headset: what it is, its address, and the colour it was made in. */
    private class Shown<K>(val piece: Modeller.Piece<K>, val entity: Entity, val uri: Uri, val first: Triple<Float, Float, Float>)

    /** A part that moves: its block (its home), its place in the list (its phase), and its mesh. */
    private class Mover<K>(val block: Block<K>, val index: Int, val shown: Shown<K>)

    private var still: List<Shown<K>> = emptyList()
    private var movers: List<Mover<K>> = emptyList()
    private var showing = BooleanArray(0)
    private var builtFor: List<Float>? = null
    private var seat: Pose? = null
    private var shown = false
    private var lit: Triple<Float, Triple<Float, Float, Float>?, Triple<Float, Float, Float>?>? = null

    /**
     * The [blocks] round [seat] (on the floor, facing the screen). Made again
     * only when the seat or [key] (whatever the blocks were worked out from)
     * changes, so it's cheap to ask each tick.
     */
    fun build(seat: Pose, key: List<Float>, blocks: () -> List<Block<K>>) {
        val wanted = listOf(seat.t.x, seat.t.y, seat.t.z, seat.q.w, seat.q.x, seat.q.y, seat.q.z) + key
        if (wanted == builtFor) return
        clear()
        builtFor = wanted
        this.seat = seat
        val modeller = Modeller(::tileOf, shaded, sided, fivefold)
        val moving = mutableListOf<Mover<K>>()
        blocks().forEachIndexed { i, b ->
            if (moves(b, i, 0f) != null) {
                // Made round its own middle, so moving it is moving its Transform.
                val own = Modeller<K>(::tileOf)
                own.part(b.kind, b.x)
                shape(Block(b.kind, 0f, 0f, 0f, b.w, b.h, b.d), own)
                val whole = MeshData().also { into -> own.meshes.values.forEach { merge(it, into) } }
                val piece = Modeller.Piece(b.kind, Side.of(b.x), Facing.SCREENWARD)
                moving += Mover(b, i, show(piece, whole, Pose(at(seat, b, 0f, 0f, 0f), seat.q)))
            } else {
                modeller.part(b.kind, b.x)
                shape(b, modeller)
            }
        }
        still = modeller.meshes.map { (piece, mesh) -> show(piece, mesh, Pose(seat.t, seat.q)) }
        movers = moving
        showing = BooleanArray(movers.size) { shown }
        lit = null
    }

    private fun tileOf(kind: K): Pair<Float, Float>? = surface(kind)?.let { it.across to it.up }

    private fun show(piece: Modeller.Piece<K>, mesh: MeshData, pose: Pose): Shown<K> {
        val textured = surface(piece.kind)
        val first = firstColour(piece)
        val uri = ModelMeshes.add(mesh)
        val e = Entity.create(listOf(
            Mesh(uri, hittable = MeshCollision.NoCollision),
            partMaterial(first, textured),
            Transform(pose),
            Visible(shown),
        ))
        return Shown(piece, e, uri, first)
    }

    /** A piece's colour under full house lights: what a plain part is made in. */
    private fun firstColour(piece: Modeller.Piece<K>): Triple<Float, Float, Float> {
        val c = colour(piece.kind, 1f, null)
        return if (!shaded(piece.kind)) c else piece.facing.shade(c, 1f)
    }

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        still.forEach { it.entity.setComponent(Visible(on)) }
        movers.forEachIndexed { i, m -> m.shown.entity.setComponent(Visible(on)); showing[i] = on }
    }

    /**
     * The house lights at [level] (1 up, low in a film) and the film's light
     * on what faces it: [left] from the picture's left half on what's on
     * your left, [right] on your right, both on what's between.
     */
    fun light(level: Float, left: Triple<Float, Float, Float>?, right: Triple<Float, Float, Float>? = left) {
        val now = Triple(level, left, right)
        if (lit == now || (still.isEmpty() && movers.isEmpty())) return
        lit = now
        val middle = if (left != null && right != null) Triple((left.first + right.first) / 2, (left.second + right.second) / 2, (left.third + right.third) / 2)
            else left ?: right
        fun relight(s: Shown<K>) {
            val tint = when (s.piece.side) { Side.LEFT -> left ?: middle; Side.RIGHT -> right ?: middle; Side.MIDDLE -> middle }
            val c = colour(s.piece.kind, level, tint)
            val faced = if (!shaded(s.piece.kind)) c else s.piece.facing.shade(c, level)
            val a = albedo(faced, s.first, surface(s.piece.kind) != null)
            ModelMeshes.light(s.uri, a[0], a[1], a[2])
        }
        still.forEach(::relight)
        movers.forEach { relight(it.shown) }
    }

    /** What moves, where it is [t] seconds in: flames flicker, fireflies wander and glow. Each frame, while shown. */
    fun animate(t: Float) {
        val s = seat ?: return
        if (!shown) return
        for ((i, m) in movers.withIndex()) {
            val sway = moves(m.block, m.index, t) ?: continue
            m.shown.entity.setComponent(Transform(Pose(at(s, m.block, sway.dx, sway.dy, sway.dz), s.q)))
            if (sway.lit != showing[i]) { showing[i] = sway.lit; m.shown.entity.setComponent(Visible(sway.lit)) }
        }
    }

    fun clear() {
        (still + movers.map { it.shown }).forEach { s ->
            runCatching { s.entity.destroy() }
            ModelMeshes.remove(s.uri)
        }
        still = emptyList()
        movers = emptyList()
        builtFor = null
        seat = null
    }

    private fun at(seat: Pose, p: Block<K>, dx: Float, dy: Float, dz: Float) =
        seat.t + seat.q * Vector3(p.x + dx, p.y + dy, p.z + dz)

    private companion object {
        /** [from]'s triangles added to [into]. */
        fun merge(from: MeshData, into: MeshData) {
            val p = from.positions(); val n = from.normals(); val t = from.uvs(); val ix = from.indices()
            val base = into.vertices
            for (i in 0 until from.vertices)
                into.vertex(p[3 * i], p[3 * i + 1], p[3 * i + 2], n[3 * i], n[3 * i + 1], n[3 * i + 2], t[2 * i], t[2 * i + 1])
            for (k in ix.indices step 3) into.triangle(base + ix[k], base + ix[k + 1], base + ix[k + 2])
        }
    }
}
