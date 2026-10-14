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
 * the front curtain, raised [curtainRise] metres out of sight to open. Only
 * if the SDK says the model couldn't be loaded is it given up on
 * ([failedNow]) and the place's modelled blocks shown instead: a model that
 * is slow to say it's ready, or whose materials can't be read for dimming,
 * stays up as it is.
 */
class BakedPlace(
    private val model: String,
    private val curtainModel: String?,
    private val curtainRise: Float,
    /** The SDK's scene object for an entity, once its mesh has loaded. */
    private val sceneObjects: (Entity) -> CompletableFuture<SceneObject>?,
    /** A picture from the app's assets (a baked atlas), or null. */
    private val picture: (String) -> android.graphics.Bitmap? = { null },
    /** A baked atlas from the app's drawables, by name, as the SDK loads a resource; or null. */
    private val resourceTexture: (String) -> com.meta.spatial.runtime.SceneTexture? = { null },
) {
    enum class State { NONE, LOADING, READY, FAILED }

    private class Lit(val material: SceneMaterial, val kind: BakedLight.Kind, val side: Side)

    @Volatile var state = State.NONE
        private set
    @Volatile private var lit: List<Lit> = emptyList()
    @Volatile private var curtainLit: List<Lit> = emptyList()
    /** The loaded models, kept to read their materials again if they weren't ready the first time. */
    @Volatile private var hallObject: SceneObject? = null
    @Volatile private var curtainObject: SceneObject? = null
    @Volatile private var broken = false
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
        app.lumiere.android.Probe.info("places", path, "loading")
        app.lumiere.android.Breadcrumbs.mark("loading model $path")
        val e = Entity.create(listOf(
            Mesh(Uri.parse("apk:///$path"), hittable = MeshCollision.NoCollision),
            Transform(at),
            Visible(visible),
        ))
        val future = runCatching { sceneObjects(e) }
            .onFailure { app.lumiere.android.Probe.fail("places", path, "the scene object couldn't be asked for: ${app.lumiere.android.Probe.why(it)}") }
            .getOrNull()
        if (future == null) app.lumiere.android.Probe.fail("places", path, "no scene object for the model (the SDK gave none)")
        future?.whenComplete { obj, error ->
            if (error != null || obj == null) {
                android.util.Log.w("Lumiere", "$path didn't load", error)
                app.lumiere.android.Probe.fail("places", path, "the model didn't load: ${app.lumiere.android.Probe.why(error)}")
                if (path == model) broken = true
                return@whenComplete
            }
            app.lumiere.android.Breadcrumbs.mark("model loaded $path")
            if (path == model) { hallObject = obj; state = State.READY } else curtainObject = obj
            done(materialsOf(obj, path))
        }
        return e
    }

    /** Textures already put on materials, by material handle, kept alive with them. */
    private val textured = java.util.concurrent.ConcurrentHashMap<Long, com.meta.spatial.runtime.SceneTexture>()
    private val pictures = java.util.concurrent.ConcurrentHashMap<Long, android.graphics.Bitmap>()

    /** A few seconds on: what the GPU's copy of an atlas averages to, beside the picture's own — white on the GPU means the copy failed. */
    private fun checkLater(file: String, texture: com.meta.spatial.runtime.SceneTexture) {
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            runCatching {
                val gpu = FloatArray(4)
                val read = texture.readAverageColor(gpu, 0, 0.5f, 0.5f)
                val white = read && gpu[0] > 0.97f && gpu[1] > 0.97f && gpu[2] > 0.97f
                app.lumiere.android.Probe.report("places", "$file on the GPU", if (white) app.lumiere.android.Probe.Status.FAIL else app.lumiere.android.Probe.Status.OK,
                    "GPU average ${if (read) "%.2f/%.2f/%.2f".format(gpu[0], gpu[1], gpu[2]) else "unreadable"}" + (if (white) " — WHITE ON THE GPU" else ""))
            }.onFailure { app.lumiere.android.Probe.warn("places", "$file on the GPU", "couldn't read: ${app.lumiere.android.Probe.why(it)}") }
        }, 4000)
    }

    /**
     * [obj]'s materials, unlit, each baked surface given its atlas from
     * environments/<model>/<material>.jpg (Scripts/env/textures.py): the
     * SDK's glTF loader may leave a baked material without its picture, and
     * the place then shows white.
     */
    private fun materialsOf(obj: SceneObject, path: String): List<Lit> = runCatching {
        val mesh = obj.mesh ?: return emptyList<Lit>().also { app.lumiere.android.Probe.warn("places", path, "loaded, but its mesh isn't readable yet") }
        val folder = path.removeSuffix(".glb")
        val materials = mesh.materials ?: return emptyList<Lit>().also { app.lumiere.android.Probe.warn("places", path, "loaded, but its materials aren't readable yet") }
        var baked = 0; var applied = 0; var unlitFailed = 0
        val missing = mutableListOf<String>(); val failed = mutableListOf<String>()
        val out = materials.mapIndexed { i, m ->
            val name = runCatching { mesh.getMaterialName(i) }.getOrDefault("")
            runCatching { m.setUnlit(true) }.onFailure { unlitFailed++ }
            if (name.endsWith("/baked")) baked++
            if (name.endsWith("/baked") && textured.containsKey(m.handle)) applied++
            if (name.endsWith("/baked") && !textured.containsKey(m.handle)) runCatching {
                // The atlas as an app resource, loaded the SDK's own way (as the skies are): a texture made
                // from a decoded picture reached the GPU white, every one (Diagnostics compared them).
                val file = "atlas_" + (folder.substringAfterLast('/') + "_" + name.replace('/', '_').replace('@', '_').replace(':', '_'))
                    .lowercase().replace(Regex("[^a-z0-9_]"), "_")
                val texture = resourceTexture(file)
                if (texture == null) missing += file
                else {
                    app.lumiere.android.Breadcrumbs.mark("texture $file onto $name")
                    m.setAlbedoTexture(texture)
                    textured[m.handle] = texture
                    checkLater(file, texture)
                    applied++
                }
            }.onFailure { android.util.Log.w("Lumiere", "$name's atlas couldn't be put on", it); failed += "$name (${app.lumiere.android.Probe.why(it)})" }
            Lit(m, BakedLight.kindOf(name), BakedLight.sideOf(name))
        }
        val summary = "${materials.size} materials, $baked baked, $applied atlases on" +
            (if (unlitFailed > 0) ", $unlitFailed couldn't be made unlit" else "") +
            (if (missing.isNotEmpty()) "; atlases not found: ${missing.joinToString()}" else "") +
            (if (failed.isNotEmpty()) "; atlases that failed: ${failed.joinToString()}" else "")
        when {
            missing.isNotEmpty() || failed.isNotEmpty() -> app.lumiere.android.Probe.fail("places", path, summary)
            baked > 0 && applied < baked -> app.lumiere.android.Probe.warn("places", path, summary)
            materials.isEmpty() -> app.lumiere.android.Probe.warn("places", path, "loaded with no materials")
            else -> app.lumiere.android.Probe.ok("places", path, summary)
        }
        out
    }.onFailure { app.lumiere.android.Probe.fail("places", path, "materials couldn't be read: ${app.lumiere.android.Probe.why(it)}") }
        .getOrDefault(emptyList())

    /**
     * Unloaded: its models and their pictures let go, for the memory they hold
     * (a place's atlases are up to 200 MB). Made again the next time it's placed.
     */
    fun release() {
        if (hall == null && curtain == null) return
        runCatching { hall?.destroy() }; runCatching { curtain?.destroy() }
        hall = null; curtain = null; hallObject = null; curtainObject = null
        lit = emptyList(); curtainLit = emptyList(); lastLight = null
        textured.values.forEach { runCatching { it.destroy() } }; textured.clear(); pictures.clear()
        origin = null; shown = false; curtainAt = Float.NaN
        if (state != State.FAILED) state = State.NONE
        app.lumiere.android.Probe.info("places", model, "released (left it): made again when you come back")
        app.lumiere.android.Breadcrumbs.mark("released $model")
    }

    fun show(on: Boolean) {
        if (on == shown) return
        shown = on
        hall?.setComponent(Visible(on))
        curtainAt = Float.NaN
    }

    /** As Scenery.light: the house lights at [level], the picture's halves' light on each side. */
    fun light(level: Float, left: Triple<Float, Float, Float>?, right: Triple<Float, Float, Float>? = left) {
        // Materials not readable when it loaded: try again (no dimming meanwhile, but the place is there).
        if (lit.isEmpty()) hallObject?.let { o -> materialsOf(o, model).takeIf { it.isNotEmpty() }?.let { lit = it; lastLight = null } }
        if (curtainLit.isEmpty()) curtainObject?.let { o -> materialsOf(o, curtainModel ?: model).takeIf { it.isNotEmpty() }?.let { curtainLit = it; lastLight = null } }
        val now = Triple(level, left, right)
        if (now == lastLight || (lit.isEmpty() && curtainLit.isEmpty())) return
        lastLight = now
        lit.firstOrNull()?.let { l ->
            val a = BakedLight.albedo(l.kind, level, left)
            app.lumiere.android.Probe.info("places", "$model light", "house lights ${"%.2f".format(level)}, drawn at ${"%.2f".format(a[0])}/${"%.2f".format(a[1])}/${"%.2f".format(a[2])} of full" +
                (if (a.maxOrNull() ?: 0f < 0.15f) " — VERY DARK" else ""))
        }
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
        if (broken && state != State.FAILED) {
            state = State.FAILED
            android.util.Log.w("Lumiere", "$model couldn't be loaded: the modelled hall instead")
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
