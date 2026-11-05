package app.lumiere.android.spatial

import android.content.Context
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3

/**
 * Where the Theater's screen goes in your room, and how big, remembered on
 * the headset: floating before you at a share of your view, or hung on a
 * wall of your room (Space Setup's, WallMount) — or, where no wall could be
 * had, pinned in the air where you looked. A mount stays until taken off,
 * so every film after goes back to the same wall.
 */
class ScreenPlace(context: Context) {
    private val prefs = context.getSharedPreferences("quest.screen", Context.MODE_PRIVATE)

    /** 0 smallest … TheaterGeometry.SIZE_DEGREES.size - 1 largest. */
    var size: Int = prefs.getInt("size", TheaterGeometry.DEFAULT_SIZE).coerceIn(0, TheaterGeometry.SIZE_DEGREES.size - 1)
        set(v) { field = v.coerceIn(0, TheaterGeometry.SIZE_DEGREES.size - 1); prefs.edit().putInt("size", field).apply() }

    /** TV Mode's size (TvMode.INCHES), for a screen on your wall or pinned in the air. */
    var tvSize: Int = prefs.getInt("tvSize", TvMode.DEFAULT).coerceIn(0, TvMode.INCHES.lastIndex)
        set(v) { field = v.coerceIn(0, TvMode.INCHES.lastIndex); prefs.edit().putInt("tvSize", field).apply() }

    /** Near, Middle or Far (TheaterGeometry.SEAT_NAMES). */
    var seat: Int = prefs.getInt("seat", 1).coerceIn(0, TheaterGeometry.SEAT_NAMES.size - 1)
        set(v) { field = v.coerceIn(0, TheaterGeometry.SEAT_NAMES.size - 1); prefs.edit().putInt("seat", field).apply() }

    /** Where films play: your room, or a place round you (Places). */
    var where: Place = Place.named(prefs.getString("place", null))
        set(v) { field = v; prefs.edit().putString("place", v.name).apply() }

    /** A title's own picture kind, chosen in the player's 3D menu; null: worked out (StereoDetect). */
    fun formatFor(itemId: String): StereoDetect.Format? =
        prefs.getString("format.$itemId", null)?.let { n -> StereoDetect.Format.entries.firstOrNull { it.name == n } }

    fun setFormat(itemId: String, format: StereoDetect.Format?) {
        prefs.edit().apply { if (format == null) remove("format.$itemId") else putString("format.$itemId", format.name) }.apply()
    }

    /** On a wall ([wall] its id and ([x], [y]) on it), or pinned in the air ([wall] null, at [at] facing [yaw]). */
    data class Mount(val wall: String?, val x: Float, val y: Float, val at: Vector3 = Vector3(0f), val yaw: Float = 0f)

    var mount: Mount? = read()
        set(v) {
            field = v
            prefs.edit().apply {
                if (v == null) remove("mounted") else {
                    putBoolean("mounted", true); putString("wall", v.wall); putFloat("x", v.x); putFloat("y", v.y)
                    putFloat("ax", v.at.x); putFloat("ay", v.at.y); putFloat("az", v.at.z); putFloat("yaw", v.yaw)
                }
            }.apply()
        }

    private fun read(): Mount? = if (!prefs.getBoolean("mounted", false)) null else Mount(
        prefs.getString("wall", null), prefs.getFloat("x", 0f), prefs.getFloat("y", 0f),
        Vector3(prefs.getFloat("ax", 0f), prefs.getFloat("ay", 1.3f), prefs.getFloat("az", 2f)), prefs.getFloat("yaw", 0f),
    )

    companion object {
        /** How far ahead a screen pinned in the air goes. */
        const val PIN_DISTANCE_M = 2.5f

        /** A pinned screen's pose from where it was pinned. */
        fun pinnedPose(m: Mount): Pose = Pose(m.at, Quaternion.fromDirection(Vector3(kotlin.math.sin(m.yaw), 0f, kotlin.math.cos(m.yaw))))

        /** The names Screen Size offers, smallest first. */
        val SIZE_NAMES = listOf("Small", "Medium", "Large", "Very Large", "Cinema")
    }
}
