package app.lumiere.android.spatial

import android.content.Context
import android.net.Uri
import androidx.core.net.toUri
import com.meta.spatial.core.Entity
import com.meta.spatial.runtime.MaterialSidedness
import com.meta.spatial.runtime.SceneMaterial
import com.meta.spatial.runtime.SceneMesh
import com.meta.spatial.toolkit.Material
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Lumiere's own meshes on the headset: a place's modelled parts
 * (Modeller), each waiting here under a number until the SDK asks for it —
 * an entity's Mesh is mesh://lumiere?id=N — and then made with the
 * entity's Material just as the SDK makes its own boxes, but double-sided,
 * so a face shows whichever way round it was wound.
 *
 * Each keeps its material, to be relit: a Material's base colour is read
 * only when its mesh is made, and not at all once it has a texture, so
 * changing it afterwards changes nothing on screen. The light goes onto the
 * material's albedo instead, in full precision (the SDK's own override
 * takes eight-bit colours, which band in a dark hall).
 */
object ModelMeshes {
    const val BASE = "mesh://lumiere"

    private class Made(val mesh: MeshData) {
        @Volatile var material: SceneMaterial? = null
        /** The albedo it should have now, linear; null leaves the material's own. */
        @Volatile var albedo: FloatArray? = null
    }

    private val made = ConcurrentHashMap<Long, Made>()
    private val next = AtomicLong(1)

    /** [mesh], to be asked for at the returned address. */
    fun add(mesh: MeshData): Uri {
        val id = next.getAndIncrement()
        made[id] = Made(mesh)
        return "$BASE?id=$id".toUri()
    }

    /** Done with: its entity is gone. */
    fun remove(uri: Uri) { idOf(uri)?.let(made::remove) }

    /** The light on [uri]'s material: [r], [g], [b] linear, multiplying its texture (or its first colour). */
    fun light(uri: Uri, r: Float, g: Float, b: Float) {
        val m = idOf(uri)?.let(made::get) ?: return
        val albedo = floatArrayOf(r, g, b)
        if (m.albedo?.contentEquals(albedo) == true) return
        m.albedo = albedo
        m.material?.let { apply(it, albedo) }
    }

    /** The SDK's call for [uri], on [entity]. */
    fun create(entity: Entity, uri: Uri, context: Context): SceneMesh {
        val material = runCatching { entity.getComponent<Material>() }.getOrElse { Material() }.generateSceneMaterial(entity, context)
        runCatching { material.setSidedness(MaterialSidedness.DOUBLE_SIDED) }
        val m = idOf(uri)?.let(made::get)
        val mesh = m?.mesh
        if (mesh == null || mesh.indexCount == 0) return SceneMesh.box(-0.001f, -0.001f, -0.001f, 0.001f, 0.001f, 0.001f, material)
        m.material = material
        m.albedo?.let { apply(material, it) }
        // Made as the SDK makes its own 3D text: one material over every index.
        return runCatching {
            SceneMesh.meshWithMaterials(
                mesh.positions(), mesh.normals(), mesh.uvs(), IntArray(mesh.vertices) { -1 }, mesh.indices(),
                intArrayOf(0, mesh.indexCount), arrayOf(material), false,
            )
        }.getOrElse {
            android.util.Log.e("Lumiere", "a modelled mesh couldn't be made", it)
            SceneMesh.box(-0.001f, -0.001f, -0.001f, 0.001f, 0.001f, 0.001f, material)
        }
    }

    private fun apply(material: SceneMaterial, albedo: FloatArray) {
        runCatching { material.setAlbedoColor(android.graphics.Color.valueOf(albedo[0], albedo[1], albedo[2], 1f)) }
    }

    private fun idOf(uri: Uri): Long? = uri.getQueryParameter("id")?.toLongOrNull()
}
