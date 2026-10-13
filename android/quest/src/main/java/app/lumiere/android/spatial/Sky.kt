package app.lumiere.android.spatial

import androidx.core.net.toUri
import app.lumiere.android.Stage
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Material
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * The sky round you, a picture for each place that has one: in space a
 * night sky with the Milky Way across it (lumiere_starfield, drawn by
 * Scripts/starfield.py); at the lakeside, and through the cabin's windows, a
 * lake at dusk (lumiere_lakeside). The SDK's own skybox, a sphere far beyond
 * everything else, unlit so it costs no lighting. One for each picture, made
 * the first time it's wanted and hidden, not unmade, when you leave: a
 * picture changed on a Material may not be loaded again on the headset, so
 * a sky never swaps its picture.
 */
class Sky {
    private val made = HashMap<Int, Entity>()
    private var shown: Int? = null

    /** Which way the shown picture's middle faces: ahead of your seat, for a place's 360° picture. */
    private var facing = com.meta.spatial.core.Quaternion()

    /** The shown picture turned so its middle is [q]'s ahead (a room's screen side). */
    fun face(seat: com.meta.spatial.core.Quaternion) {
        // The skybox's picture faces the other way from a seat's ahead: turned half round, its middle is ahead.
        val q = seat * com.meta.spatial.core.Quaternion(0f, 0f, 1f, 0f)  // (w, x, y, z): half round about the up axis
        if (q == facing) return
        facing = q
        shown?.let { made[it]?.setComponent(Transform(Pose(Vector3(0f), q))) }
    }

    /** A change of picture under way: dimming the old one, then brightening the new (0 none, 1 out, 2 in). */
    private var phase = 0
    private var pending: Int? = null
    private var since = 0L
    /** True while fading. */
    val fading: Boolean get() = phase != 0

    /**
     * To [picture] with a fade, as house lights go down and up: the one shown dims nearly to black, the
     * other takes its place there and comes up. Call [step] each frame until [fading] is false.
     */
    fun fadeTo(picture: Int?, now: Long) {
        if (phase == 0 && picture == shown) return
        if (phase != 0 && picture == pending) return
        pending = picture; phase = 1; since = now
    }

    /** One frame of a fade; true while there's more. */
    fun step(now: Long): Boolean {
        if (phase == 0) return false
        val t = (now - since).toFloat()
        if (phase == 1) {
            if (t >= OUT_MS) { show(pending); phase = 2; since = now; light(LOW); return true }
            val k = t / OUT_MS
            light(1f - (1f - LOW) * k * k * (3 - 2 * k))
        } else {
            if (t >= IN_MS) { phase = 0; light(1f); return false }
            val k = t / IN_MS
            light(LOW + (1f - LOW) * k * k * (3 - 2 * k))
        }
        return true
    }

    /** The shown sky's picture at [level] of its own brightness. */
    private fun light(level: Float) {
        val e = shown?.let { made[it] } ?: return
        val obj = runCatching { objects?.invoke(e)?.getNow(null) }.getOrNull() ?: return
        runCatching { obj.mesh?.materials?.forEach { it.setAlbedoColor(android.graphics.Color.valueOf(level, level, level, 1f)) } }
    }

    /** The sky with [picture] (a drawable) round you; none for null. */
    fun show(picture: Int?) {
        if (picture == shown) return
        shown?.let { made[it]?.setComponent(Visible(false)) }
        shown = picture
        if (picture == null) return
        val sky = made[picture]
        if (sky != null) { sky.setComponent(Transform(Pose(Vector3(0f), facing))); sky.setComponent(Visible(true)); return }
        made[picture] = Entity.create(listOf(
            Mesh("mesh://skybox".toUri(), hittable = MeshCollision.NoCollision),
            Material().apply { baseTextureAndroidResourceId = picture; unlit = true },
            Transform(Pose(Vector3(0f), facing)),
            Visible(true),
        ))
    }

    companion object {
        /** The SDK's scene object for an entity (LumiereSpace), for the fade to dim a sky's material. */
        var objects: ((Entity) -> java.util.concurrent.CompletableFuture<com.meta.spatial.runtime.SceneObject>?)? = null
        const val OUT_MS = 1400f
        const val IN_MS = 1800f
        const val LOW = 0.08f

        /** Each place's 360° picture rendered from its seat (pano_<place>), as LumiereSpace finds them. */
        var panoramas: Map<Stage.Place, Int> = emptyMap()
        /** The same with the house lights down, for while a film plays (pano_<place>_dark). */
        var darkPanoramas: Map<Stage.Place, Int> = emptyMap()

        /** The picture round you in [place]: stars in space, the lake at the lakeside and outside the cabin; none elsewhere. */
        fun pictureFor(place: Stage.Place): Int? = when (place) {
            Stage.Place.SPACE -> R.drawable.lumiere_starfield
            Stage.Place.LAKE, Stage.Place.CABIN -> R.drawable.lumiere_lakeside
            Stage.Place.CLOUDS -> R.drawable.lumiere_clouds
            Stage.Place.MOON -> R.drawable.lumiere_moon
            Stage.Place.STATION -> R.drawable.lumiere_orbit
            Stage.Place.DRIVE_IN -> R.drawable.lumiere_drivein
            Stage.Place.ROOFTOP -> R.drawable.lumiere_city
            Stage.Place.WINTER -> R.drawable.lumiere_winter
            Stage.Place.SEA -> R.drawable.lumiere_sea
            Stage.Place.ROOM, Stage.Place.CINEMA, Stage.Place.VOID, Stage.Place.PALACE -> null
        }
    }
}
