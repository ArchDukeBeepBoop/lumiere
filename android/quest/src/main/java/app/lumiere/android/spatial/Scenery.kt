package app.lumiere.android.spatial

import androidx.core.net.toUri
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Box
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * A place's surroundings made from its blocks round your seat, as the
 * Theatre makes the cinema's hall: each box at its real size (corners given
 * to the Box the SDK reads, never a Scale, which the headset doesn't apply),
 * with unlit colours worked out here from the house lights and the film's
 * colour by [colour], over the [surface] it's made of (wood, stone, cloth),
 * so it costs no lighting on the headset and changes only when the light
 * does. What [moves] — a flame, a firefly — is moved each frame by
 * [animate]. The cabin and the lakeside's pontoon are each one.
 */
class Scenery<K>(
    private val colour: (K, Float, Triple<Float, Float, Float>?) -> Triple<Float, Float, Float>,
    private val surface: (K) -> Surface? = { null },
    private val moves: (K, Int, Float) -> Life.Sway? = { _, _, _ -> null },
) {
    private var parts: List<Pair<Block<K>, Entity>> = emptyList()
    private var builtFor: List<Float>? = null
    private var seat: Pose? = null
    private var shown = false
    private var lit: Pair<Float, Triple<Float, Float, Float>?>? = null
    /** The parts that move, and whether each is showing now. */
    private var moving: List<Int> = emptyList()
    private var showing = BooleanArray(0)

    /**
     * The [blocks] round [seat] (on the floor, facing the screen). Made again
     * only when the seat or [key] (whatever the blocks were worked out from)
     * changes, so it's cheap to ask each tick.
     */
    fun build(seat: Pose, key: List<Float>, blocks: () -> List<Block<K>>) {
        val wanted = listOf(seat.t.x, seat.t.z, seat.q.w, seat.q.y) + key
        if (wanted == builtFor) return
        clear()
        builtFor = wanted
        this.seat = seat
        parts = blocks().map { p ->
            p to Entity.create(listOf(
                Mesh("mesh://box".toUri(), hittable = MeshCollision.NoCollision),
                Box(Vector3(-p.w / 2, -p.h / 2, -p.d / 2), Vector3(p.w / 2, p.h / 2, p.d / 2)),
                boxMaterial(colour(p.kind, 1f, null), surface(p.kind), p.w, p.h, p.d),
                Transform(Pose(at(seat, p, 0f, 0f, 0f), seat.q)),
                Visible(shown),
            ))
        }
        moving = parts.indices.filter { i -> moves(parts[i].first.kind, i, 0f) != null }
        showing = BooleanArray(parts.size) { shown }
        lit = null
    }

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        parts.forEachIndexed { i, (_, e) -> e.setComponent(Visible(on)); showing[i] = on }
    }

    /** The house lights at [level] (1 up, low in a film) and the film's [tint] on what faces it. */
    fun light(level: Float, tint: Triple<Float, Float, Float>?) {
        if (lit == level to tint || parts.isEmpty()) return
        lit = level to tint
        parts.forEach { (p, e) -> e.setComponent(boxMaterial(colour(p.kind, level, tint), surface(p.kind), p.w, p.h, p.d)) }
    }

    /** What moves, where it is [t] seconds in: flames flicker, fireflies wander and glow. Each frame, while shown. */
    fun animate(t: Float) {
        val s = seat ?: return
        if (!shown) return
        for (i in moving) {
            val (p, e) = parts[i]
            val sway = moves(p.kind, i, t) ?: continue
            e.setComponent(Transform(Pose(at(s, p, sway.dx, sway.dy, sway.dz), s.q)))
            if (sway.lit != showing[i]) { showing[i] = sway.lit; e.setComponent(Visible(sway.lit)) }
        }
    }

    fun clear() {
        parts.forEach { (_, e) -> runCatching { e.destroy() } }
        parts = emptyList()
        moving = emptyList()
        builtFor = null
        seat = null
    }

    private fun at(seat: Pose, p: Block<K>, dx: Float, dy: Float, dz: Float) =
        seat.t + seat.q * Vector3(p.x + dx, p.y + dy, p.z + dz)
}
