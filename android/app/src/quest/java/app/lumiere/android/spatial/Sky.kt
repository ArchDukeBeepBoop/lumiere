package app.lumiere.android.spatial

import androidx.core.net.toUri
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Material
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform

/**
 * The picture round you in a place: the SDK's skybox, unlit, a sphere far
 * beyond everything else, its middle turned to face your seat's ahead.
 *
 * **Exactly one at a time.** The spatial app kept a hidden skybox for every
 * picture it had shown; the moment there were two, every one of them drew
 * white in the headset, the one that had worked included. And a picture
 * changed on a Material isn't loaded again there (docs/quest/HANDOVER.md
 * §3). So a new picture always means the old sky unmade, then a new one
 * made with a Material of its own.
 */
class Sky(private val sceneObjects: (Entity) -> java.util.concurrent.CompletableFuture<com.meta.spatial.runtime.SceneObject>?) {
    private var sky: Entity? = null
    private var shown: Int? = null
    private var level = 1f
    private var tint: FilmLight.Rgb? = null
    private var applied: Triple<Float, Float, Float>? = null

    /** [picture] (a drawable) round you, its middle ahead along [yaw] radians, at [brightness]; none for null. */
    fun show(picture: Int?, yaw: Float, brightness: Float = 1f) {
        if (picture != shown) {
            sky?.let { runCatching { it.destroy() } }
            sky = null
            shown = picture
            if (picture != null) sky = Entity.create(listOf(
                Mesh("mesh://skybox".toUri(), hittable = MeshCollision.NoCollision),
                Material().apply { baseTextureAndroidResourceId = picture; unlit = true },
                Transform(Pose(Vector3(0f), facing(yaw))),
            ))
            level = 1f
            applied = null
            tint = null
        } else sky?.setComponent(Transform(Pose(Vector3(0f), facing(yaw))))
        level = brightness
        apply()
    }

    /** The film's colour on the place's light (FilmLight); null: plain. */
    fun tint(colour: FilmLight.Rgb?) { tint = colour; apply() }

    /**
     * The picture at [brightness] of its own, as house lights going down
     * where a place has no dark picture of its own. The SDK may not honour
     * a skybox's albedo (unconfirmed on the headset); the room stays lit then.
     */
    private fun apply() {
        val want = FilmLight.light(level, tint)
        if (want == applied || (applied == null && want == Triple(1f, 1f, 1f))) return
        val e = sky ?: return
        applied = want
        sceneObjects(e)?.thenAccept { obj ->
            runCatching { obj.mesh?.materials?.forEach { it.setAlbedoColor(android.graphics.Color.valueOf(want.first, want.second, want.third, 1f)) } }
        }
    }

    fun clear() = show(null, 0f)

    /**
     * The skybox's picture faces the other way from a seat's ahead: turned
     * half round about the up axis as well, its middle is ahead of you.
     * Quaternion is (w, x, y, z): w first (HANDOVER §3).
     */
    private fun facing(yaw: Float): Quaternion =
        Quaternion.fromDirection(Vector3(kotlin.math.sin(yaw), 0f, kotlin.math.cos(yaw))) * Quaternion(0f, 0f, 1f, 0f)
}
