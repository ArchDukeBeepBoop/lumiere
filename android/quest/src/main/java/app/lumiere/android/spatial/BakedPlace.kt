package app.lumiere.android.spatial

import android.net.Uri
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.SceneMaterial
import com.meta.spatial.runtime.SceneObject
import com.meta.spatial.toolkit.Mesh
import com.meta.spatial.toolkit.MeshCollision
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible
import java.util.concurrent.CompletableFuture

/**
 * A place modelled and lit in Blender, its light baked into its textures
 * (Scripts/env): a glTF model among the app's assets, drawn unlit as a game
 * draws its levels — soft shadows, light pooling under the lamps and bounced
 * off the walls, at no cost on the headset. Its materials say how each part
 * takes the house lights and the film's light (BakedLight); they're dimmed
 * through their albedo, as the modelled places' are (ModelMeshes).
 *
 * [model] is placed by its origin ([place]); an optional [curtainModel] is
 * the front curtain, raised [curtainRise] metres out of sight to open. If
 * the model hasn't loaded in [LOAD_TIMEOUT_MS] it's given up on ([failedNow])
 * and the place shows its modelled blocks instead.
 */
class BakedPlace(
    private val model: String,
    private val curtainModel: String?,
    private val curtainRise: Float,
    /** The SDK's scene object for an entity, once its mesh has loaded. */
    private val sceneObjects: (Entity) -> CompletableFuture<SceneObject>?,
) {
    enum class State { NONE, LOADING, READY, FAILED }

    private class Lit(val material: SceneMaterial, val kind: BakedLight.Kind, val side: Side)

    @Volatile var state = State.NONE
        private set
    @Volatile private var lit: List<Lit> = emptyList()
    @Volatile private var curtainLit: List<Lit> = emptyList()
    private var hall: Entity? = null
    private var curtain: Entity? = null
    private var origin: Pose? = null
    private var shown = false
    private var loadingSince = 0L
    private var failureTold = false
    private var lastLight: Triple<Float, Triple<Float, Float, Float>?, Triple<Float, Float, Float>?>? = null
    private var curtainAt = Float.NaN

    /** The model with its origin at [at]: made the first time, moved after. */
    fun place(at: Pose, now: Long = System.currentTimeMillis()) {
        if (state == State.FAILED) return
        if (at == origin) return
        origin = at
        val made = hall
        if (made == null) {
            hall = load(model, at, now) { lit = it; lastLight = null }
            curtainModel?.let { c -> curtain = load(c, at, now, visible = false) { curtainLit = it; lastLight = null } }
            curtainAt = Float.NaN
        } else {
            made.setComponent(Transform(at))
            curtainAt = Float.NaN
        }
    }

    private fun load(path: String, at: Pose, now: Long, visible: Boolean = shown, done: (List<Lit>) -> Unit): Entity {
        state = State.LOADING
        loadingSince = now
        val e = Entity.create(listOf(
            Mesh(Uri.parse("apk:///$path"), hittable = MeshCollision.NoCollision),
            Transform(at),
            Visible(visible),
        ))
        runCatching { sceneObjects(e) }.getOrNull()?.whenComplete { obj, error ->
            val found = if (error == null && obj != null) materialsOf(obj) else emptyList()
            if (found.isEmpty()) { android.util.Log.w("Lumiere", "$path didn't load", error); return@whenComplete }
            done(found)
            if (path == model) state = State.READY
        }
        return e
    }

    private fun materialsOf(obj: SceneObject): List<Lit> = runCatching {
        val mesh = obj.mesh ?: return emptyList()
        (mesh.materials ?: return emptyList()).mapIndexed { i, m ->
            val name = runCatching { mesh.getMaterialName(i) }.getOrDefault("")
            runCatching { m.setUnlit(true) }
            Lit(m, BakedLight.kindOf(name), BakedLight.sideOf(name))
        }
    }.getOrDefault(emptyList())

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        hall?.setComponent(Visible(on))
        curtainAt = Float.NaN
    }

    /** As Scenery.light: the house lights at [level], the picture's halves' light on each side. */
    fun light(level: Float, left: Triple<Float, Float, Float>?, right: Triple<Float, Float, Float>? = left) {
        val now = Triple(level, left, right)
        if (now == lastLight || (lit.isEmpty() && curtainLit.isEmpty())) return
        lastLight = now
        val middle = if (left != null && right != null) Triple((left.first + right.first) / 2, (left.second + right.second) / 2, (left.third + right.third) / 2)
            else left ?: right
        for (l in lit + curtainLit) {
            val tint = when (l.side) { Side.LEFT -> left ?: middle; Side.RIGHT -> right ?: middle; Side.MIDDLE -> middle }
            val a = BakedLight.albedo(l.kind, level, tint)
            runCatching { l.material.setAlbedoColor(android.graphics.Color.valueOf(a[0], a[1], a[2], 1f)) }
        }
    }

    /** The front curtain [closed] of the way down (FrontCurtain): eased, so it starts and stops softly; out of sight open. */
    fun curtain(closed: Float) {
        val c = curtain ?: return
        val at = origin ?: return
        val down = closed.coerceIn(0f, 1f).let { it * it * (3 - 2 * it) }
        if (down == curtainAt) return
        curtainAt = down
        val visible = shown && down > 0.001f
        c.setComponent(Visible(visible))
        if (visible) c.setComponent(Transform(Pose(at.t + at.q * Vector3(0f, curtainRise * (1 - down), 0f), at.q)))
    }

    /**
     * Whether the model has, as of [now], just been given up on — true once:
     * it never loaded (a missing or unreadable asset, or the SDK unable to
     * draw it). The place falls back to its modelled blocks.
     */
    fun failedNow(now: Long): Boolean {
        if (state == State.LOADING && now - loadingSince > LOAD_TIMEOUT_MS) {
            state = State.FAILED
            android.util.Log.w("Lumiere", "$model didn't load in time: the modelled hall instead")
            hall?.let { runCatching { it.destroy() } }
            curtain?.let { runCatching { it.destroy() } }
            hall = null; curtain = null
        }
        if (state == State.FAILED && !failureTold) { failureTold = true; return true }
        return false
    }

    companion object {
        const val LOAD_TIMEOUT_MS = 30_000L
    }
}

/**
 * How a baked place's materials take the light, by name (Scripts/env): a
 * surface ("…/baked") was baked with the house lights up, so up it shows as
 * baked and down it dims toward the film's light, its side ("@L", "@R") taking
 * that half of the picture; a lamp ("lamp:…") is a house light's own glass,
 * going down with them; a sign ("glow:…") stays lit. Pure, so it's tested
 * without a headset.
 */
object BakedLight {
    enum class Kind { SURFACE, LAMP, GLOW }

    fun kindOf(name: String): Kind = when {
        name.startsWith("glow:") -> Kind.GLOW
        name.startsWith("lamp:") -> Kind.LAMP
        else -> Kind.SURFACE
    }

    fun sideOf(name: String): Side = when {
        "@L" in name -> Side.LEFT
        "@R" in name -> Side.RIGHT
        else -> Side.MIDDLE
    }

    /** The film's light on the hall at most, while it's dark, and what's left of the house lights then. */
    const val FILM = 0.3f
    const val DARK = 0.22f

    /** What multiplies a [kind]'s baked colour with the house lights at [level] and the film's [tint]: linear, each 0..1. */
    fun albedo(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): FloatArray {
        val l = level.coerceIn(0f, 1f)
        return when (kind) {
            Kind.GLOW -> floatArrayOf(1f, 1f, 1f)
            Kind.LAMP -> linear(0.08f + 0.92f * l).let { floatArrayOf(it, it, it) }
            Kind.SURFACE -> {
                val (r, g, b) = tint ?: Triple(0.5f, 0.5f, 0.55f)
                val house = DARK + (1 - DARK) * l
                val film = FILM * (1 - l)
                floatArrayOf(linear((house + film * r).coerceAtMost(1f)), linear((house + film * g).coerceAtMost(1f)), linear((house + film * b).coerceAtMost(1f)))
            }
        }
    }
}
