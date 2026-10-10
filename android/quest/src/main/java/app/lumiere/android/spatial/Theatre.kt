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
 * The cinema's hall, made from Auditorium's boxes round your seat. Each box
 * is built at its real size — corners given to the Box the SDK reads, never
 * a Scale, which the headset didn't apply (the old hall's floor stayed a
 * one-metre cube you sat inside, and nothing showed). Unlit colours, worked
 * out here from the house lights and the film's colour, so it costs no
 * lighting on the headset and updates only when the light changes.
 */
class Theatre {
    private var parts: List<Pair<Auditorium.Part, Entity>> = emptyList()
    private var builtFor: List<Float>? = null
    private var shown = false
    private var lit: Pair<Float, Triple<Float, Float, Float>?>? = null

    /**
     * The hall round [seat] (on the floor, facing the screen) for a screen
     * [width] × [height] whose middle is [middleY] up and [distance] ahead.
     * Built again only when any of that changes.
     */
    fun build(seat: Pose, width: Float, height: Float, middleY: Float, distance: Float) {
        val key = listOf(seat.t.x, seat.t.z, seat.q.w, seat.q.y, width, height, middleY, distance)
        if (key == builtFor) return
        clear()
        builtFor = key
        parts = Auditorium.build(width, height, middleY, distance).map { p ->
            val at = seat.t + seat.q * Vector3(p.x, p.y, p.z)
            p to Entity.create(listOf(
                Mesh("mesh://box".toUri(), hittable = MeshCollision.NoCollision),
                Box(Vector3(-p.w / 2, -p.h / 2, -p.d / 2), Vector3(p.w / 2, p.h / 2, p.d / 2)),
                material(Auditorium.colour(p.kind, 1f, null)),
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
        parts.forEach { (p, e) -> e.setComponent(material(Auditorium.colour(p.kind, level, tint))) }
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
