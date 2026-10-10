package app.lumiere.android.spatial

import androidx.core.net.toUri
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.Material
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible

/**
 * Space: a night sky all round you, the Milky Way across it
 * (lumiere_starfield, drawn by Scripts/starfield.py). The SDK's own skybox,
 * a sphere far beyond everything else, unlit so it costs no lighting; made
 * the first time you go to space and hidden, not unmade, when you leave.
 */
class Sky {
    private var entity: Entity? = null
    private var shown = false

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        val made = entity
        if (made != null) { made.setComponent(Visible(on)); return }
        if (!on) return
        entity = Entity.create(listOf(
            Mesh("mesh://skybox".toUri(), hittable = MeshCollision.NoCollision),
            Material().apply { baseTextureAndroidResourceId = R.drawable.lumiere_starfield; unlit = true },
            Transform(Pose(Vector3(0f))),
            Visible(true),
        ))
    }
}
