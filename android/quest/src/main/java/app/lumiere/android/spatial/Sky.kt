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
    fun face(q: com.meta.spatial.core.Quaternion) {
        if (q == facing) return
        facing = q
        shown?.let { made[it]?.setComponent(Transform(Pose(Vector3(0f), q))) }
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
        /** Each place's 360° picture rendered from its seat (pano_<place>), as LumiereSpace finds them. */
        var panoramas: Map<Stage.Place, Int> = emptyMap()

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
