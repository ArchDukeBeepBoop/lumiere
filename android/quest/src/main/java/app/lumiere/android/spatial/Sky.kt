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
    fun fadeTo(picture: Int?, now: Long, level: Float = 1f) {
        if (phase == 0 && picture == shown) {
            // The same picture, only dimmer or brighter (lights down where there's no dark picture).
            if (level != end) { from = current; end = level; phase = 3; since = now }
            return
        }
        if (phase != 0 && picture == pending && level == end) return
        pending = picture; end = level; from = current; phase = 1; since = now
    }

    /** Where the brightness is now, where it's going, and where a glide set out from. */
    private var current = 1f
    private var end = 1f
    private var from = 1f

    /** One frame of a fade; true while there's more. */
    fun step(now: Long): Boolean {
        if (phase == 0) return false
        val t = (now - since).toFloat()
        fun ease(k: Float) = k * k * (3 - 2 * k)
        when (phase) {
            1 -> {
                if (t >= OUT_MS) { show(pending); phase = 2; since = now; light(LOW); return true }
                light(from + (LOW - from) * ease(t / OUT_MS))
            }
            2 -> {
                if (t >= IN_MS) { phase = 0; light(end); return false }
                light(LOW + (end - LOW) * ease(t / IN_MS))
            }
            else -> {
                if (t >= IN_MS) { phase = 0; light(end); return false }
                light(from + (end - from) * ease(t / IN_MS))
            }
        }
        return true
    }

    /** The shown sky's picture at [level] of its own brightness. */
    private fun light(level: Float) {
        current = level
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
        /** A room drawn from each of its seats, one per screen size (pano_<place>_s<size>, and _dark). */
        var seatPanoramas: Map<Pair<Stage.Place, Int>, Int> = emptyMap()
        var darkSeatPanoramas: Map<Pair<Stage.Place, Int>, Int> = emptyMap()

        /** How bright a lit picture is kept for a film where there's no dark one of that seat: the house lights down. */
        const val DIMMED = 0.32f

        /** Whether [place]'s seat for [size] has its own lights-down picture (else the lit one is [DIMMED]). */
        fun hasDark(place: Stage.Place, size: Int) = darkSeatPanoramas[place to size] != null ||
            (seatPanoramas[place to size] == null && darkPanoramas[place] != null)

        fun hasPanorama(place: Stage.Place) = panoramas[place] != null || seatPanoramas.keys.any { it.first == place }

        /** [place]'s picture from the seat for [size], lights down when [dark]: the nearest one there is. */
        fun panoramaFor(place: Stage.Place, size: Int, dark: Boolean): Int? {
            val seat = place to size
            return (if (dark) darkSeatPanoramas[seat] ?: darkPanoramas[place]?.takeIf { seatPanoramas[seat] == null } else null)
                ?: seatPanoramas[seat] ?: panoramas[place]
        }

        /**
         * How much further away the screen is put in a 360° place, and how much larger, so it looks the same
         * size: the picture round you is drawn as if far off, and a screen at its true distance stood a few
         * paces in front of the one drawn there. This far, the two are at one depth to your eyes.
         */
        const val FAR = 6f

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
