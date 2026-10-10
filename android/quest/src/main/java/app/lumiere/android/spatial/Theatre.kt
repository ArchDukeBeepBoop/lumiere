package app.lumiere.android.spatial

import androidx.core.net.toUri
import com.meta.spatial.core.Color4
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Material
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Scale
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * The cinema around the screen: a dark auditorium, a floor that catches the
 * film's light, and a low stage under the screen. Three unlit shapes and no
 * textures, so the headset draws it for almost nothing.
 */
class Theatre {
    private val sky = Entity.create(listOf(
        Mesh("mesh://skybox".toUri(), hittable = MeshCollision.NoCollision),
        material(0f, 0f, 0f), Transform(Pose(Vector3(0f))), Visible(false)))
    private val floor = Entity.create(listOf(
        Mesh("mesh://box".toUri(), hittable = MeshCollision.NoCollision),
        material(0f, 0f, 0f), Transform(Pose(Vector3(0f, -0.01f, 0f))), Scale(Vector3(60f, 0.02f, 60f)), Visible(false)))
    private val stage = Entity.create(listOf(
        Mesh("mesh://box".toUri(), hittable = MeshCollision.NoCollision),
        material(0f, 0f, 0f), Transform(Pose(Vector3(0f))), Scale(Vector3(9f, 0.6f, 1.2f)), Visible(false)))
    private var shown = false
    private var lit: Pair<Float, Triple<Float, Float, Float>?>? = null

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        listOf(sky, floor, stage).forEach { it.setComponent(Visible(on)) }
    }

    /** The stage, under a screen whose middle is at [screen], facing the same way. */
    fun place(screen: Pose, screenHeightM: Float) {
        val under = screen.t - screen.forward() * 0.6f
        stage.setComponent(Transform(Pose(Vector3(under.x, 0.3f, under.z), screen.q)))
        stage.setComponent(Scale(Vector3(screenHeightM * 1.9f, 0.6f, 1.2f)))
    }

    /**
     * The house lights at [level] (1 before the film, low while it plays) and
     * the film's colour [tint] on the floor and walls, stronger as it darkens.
     */
    fun light(level: Float, tint: Triple<Float, Float, Float>?) {
        if (lit == level to tint) return
        lit = level to tint
        val (r, g, b) = tint ?: Triple(0.5f, 0.5f, 0.5f)
        val spill = 1f - level
        fun mix(base: Float, c: Float, amount: Float) = (base * (0.25f + 0.75f * level) + c * amount * spill).coerceIn(0f, 1f)
        sky.setComponent(material(mix(0.035f, r, 0.03f), mix(0.03f, g, 0.03f), mix(0.04f, b, 0.03f)))
        floor.setComponent(material(mix(0.09f, r, 0.10f), mix(0.08f, g, 0.10f), mix(0.09f, b, 0.10f)))
        stage.setComponent(material(mix(0.06f, r, 0.16f), mix(0.05f, g, 0.16f), mix(0.06f, b, 0.16f)))
    }

    private fun material(r: Float, g: Float, b: Float) = Material().apply {
        baseColor = Color4(r, g, b, 1f)
        unlit = true
    }
}
