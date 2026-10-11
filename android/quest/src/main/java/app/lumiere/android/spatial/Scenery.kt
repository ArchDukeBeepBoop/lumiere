package app.lumiere.android.spatial

import androidx.core.net.toUri
import com.meta.spatial.core.Color4
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Box
import com.meta.spatial.toolkit.Material
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * A place's surroundings made from its blocks round your seat, as the
 * Theatre makes the cinema's hall: each box at its real size (corners given
 * to the Box the SDK reads, never a Scale, which the headset doesn't apply),
 * with unlit colours worked out here from the house lights and the film's
 * colour by [colour], so it costs no lighting on the headset and changes only
 * when the light does. The cabin and the lakeside's pontoon are each one.
 */
class Scenery<K>(private val colour: (K, Float, Triple<Float, Float, Float>?) -> Triple<Float, Float, Float>) {
    private var parts: List<Pair<Block<K>, Entity>> = emptyList()
    private var builtFor: List<Float>? = null
    private var shown = false
    private var lit: Pair<Float, Triple<Float, Float, Float>?>? = null

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
        parts = blocks().map { p ->
            val at = seat.t + seat.q * Vector3(p.x, p.y, p.z)
            p to Entity.create(listOf(
                Mesh("mesh://box".toUri(), hittable = MeshCollision.NoCollision),
                Box(Vector3(-p.w / 2, -p.h / 2, -p.d / 2), Vector3(p.w / 2, p.h / 2, p.d / 2)),
                material(colour(p.kind, 1f, null)),
                Transform(Pose(at, seat.q)),
                Visible(shown),
            ))
        }
        lit = null
    }

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        parts.forEach { (_, e) -> e.setComponent(Visible(on)) }
    }

    /** The house lights at [level] (1 up, low in a film) and the film's [tint] on what faces it. */
    fun light(level: Float, tint: Triple<Float, Float, Float>?) {
        if (lit == level to tint || parts.isEmpty()) return
        lit = level to tint
        parts.forEach { (p, e) -> e.setComponent(material(colour(p.kind, level, tint))) }
    }

    fun clear() {
        parts.forEach { (_, e) -> runCatching { e.destroy() } }
        parts = emptyList()
        builtFor = null
    }

    private fun material(c: Triple<Float, Float, Float>) = Material().apply {
        baseColor = Color4(c.first, c.second, c.third, 1f)
        unlit = true
    }
}
