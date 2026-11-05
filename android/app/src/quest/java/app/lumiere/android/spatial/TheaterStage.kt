package app.lumiere.android.spatial

import app.lumiere.android.R
import app.lumiere.android.player.Entry
import app.lumiere.android.player.Theater
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Grabbable
import com.meta.spatial.toolkit.GrabbableType
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.Scale
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.TransformParent
import com.meta.spatial.toolkit.Visible
import com.meta.spatial.toolkit.createPanelEntity

/**
 * The Theater in your room. When a film asks for a screen (Theater.request),
 * one goes up — in the place you chose, on your wall, or floating before you —
 * with its captions under it and its own bar low before you (FilmBar). The
 * window hides, showing just above the bar only for a menu or a question.
 * When the film ends all of it goes and the window returns where it was.
 */
class TheaterStage(
    private val scene: Scene,
    private val place: ScreenPlace,
    private val sky: Sky,
    private val walls: RoomWalls?,
    private val window: () -> Entity?,
) {
    private var screen: Entity? = null
    private var captions: Entity? = null
    private var made: Theater.Request? = null
    private var windowShown = true
    /** Made again on the next look: a new size, a wall just found, a mount taken off. */
    private var remake = false

    private val pops = StagePops(scene)
    private var bar: Entity? = null

    init {
        Theater.menu = ::menu
        PlacePicker.current = { place.where }
        PlacePicker.onPick = { place.where = it; remake = true }
        // The bar's own Reset View: back before you even on your wall, since you asked.
        FilmBar.resetView = { if (made != null) remake = true }
    }

    fun tick() {
        watchForReset()
        val request = Theater.request
        if (request != made || (remake && request != null)) {
            remake = false
            val keepWindow = made != null && request != null
            clearScreen()
            // Where to Watch belongs to a film: it never outlives one, or opens over a new one.
            if (!keepWindow) PlacePicker.open = false
            if (request == null) restoreWindow() else make(request, keepWindow)
        }
        // The window only for a question the player asks, before the film is up as well as during it.
        showWindow(Theater.chromeUp)
        pops.tick()
        // Your wall has its own button on the transport bar, in your own room.
        Theater.barButton = if (!WALL_MOUNT || place.where != Place.ROOM) null
            else if (place.mount == null) "TV Mode" to ::hang
            else "Leave TV Mode" to { place.mount = null; remake = true; say("The screen floats again") }
    }

    private fun make(request: Theater.Request, keepWindow: Boolean) {
        val head = scene.getViewerPose()
        val ahead = level(head.forward())
        val facing = Quaternion.fromDirection(ahead)
        // Flat, 3D, or round you: the title's own choice, else worked out from its name and shape.
        val format = place.formatFor(request.itemId) ?: StereoDetect.of(request.name, request.width, request.height)
        currentFormat = format
        if (format.sphere) {
            // 180° and 360° wrap round you: the picture is the world, so no place and no room behind it.
            current = TheaterGeometry.sized(1f, request.width, request.height, TheaterGeometry.SPHERE_RADIUS_M)
                .copy(pixelWidth = request.width.coerceIn(1, 8192), pixelHeight = request.height.coerceIn(1, 8192))
            runCatching { sky.clear() }
            runCatching { scene.enablePassthrough(false) }
            screen = Entity.createPanelEntity(R.id.lumiere_screen, Transform(Pose(head.t, facing)))
            // Captions before you, low in your view, since there's no screen's foot to hang them from.
            captions = Entity.createPanelEntity(R.id.lumiere_captions,
                Transform(Pose(head.t + ahead * SPHERE_CAPTIONS_M - Vector3(0f, SPHERE_CAPTIONS_BELOW_M, 0f), facing)))
        } else {
            // One eye's picture sets the screen's shape; the layer itself takes the whole frame, both eyes.
            val eye = (request.height * StereoDetect.eyeAspect(format, request.width, request.height)).toInt()
            val (shape, pose) = placed(request.copy(width = eye), head.t, ahead) ?: return
            val spec = shape.copy(pixelWidth = request.width.coerceIn(1, 8192), pixelHeight = request.height.coerceIn(1, 8192))
            current = spec
            // The place round you, or your own room: one sky at a time (Sky).
            val where = place.where
            val yaw = kotlin.math.atan2(ahead.x, ahead.z)
            val picture = where.pictureFor(film = true)
            runCatching { sky.show(picture?.first, yaw, picture?.second ?: 1f) }.onFailure { android.util.Log.w("Lumiere", "sky", it) }
            // The place takes on the film's colour, from its backdrop, once it's fetched (FilmLight).
            val server = app.lumiere.android.OpenApp.state?.server
            if (picture != null && server != null && request.itemId.isNotEmpty() && FilmLight.enabled())
                FilmLight.fetch(server.http, server.imageUrl(request.itemId, "Backdrop", null, 64)) { c -> if (made == request) runCatching { sky.tint(c) } }
            runCatching { scene.enablePassthrough(where.passthrough) }
            screen = Entity.createPanelEntity(R.id.lumiere_screen, Transform(pose),
                // Carried with a grip or a pinch while it floats; a place's own screen, and one on your wall, stay put.
                Grabbable(enabled = where.drawn == null && (place.mount == null || !WALL_MOUNT), type = GrabbableType.FACE)).also { s ->
                // Under the screen's foot, a little in front of it (you are toward -Z in its frame), carried with it.
                val c = TheaterGeometry.captions(spec)
                captions = Entity.createPanelEntity(R.id.lumiere_captions,
                    Transform(Pose(Vector3(0f, -c.belowMiddleM, -0.02f))), TransformParent(s))
            }
        }
        made = request
        android.util.Log.i("Lumiere", "theater: screen for ${request.width}x${request.height} ${format.name} in ${place.where.name}" +
            " mount=${place.mount?.let { if (it.wall != null) "wall" else "pinned" } ?: "none"} head=${head.t} screen=${screen?.getComponent<Transform>()?.transform?.t}")
        FilmBar.title = request.name
        FilmBar.screen = screenControls(place, format.sphere, WALL_MOUNT && place.mount != null) { remake = true }
        // The film's own bar, low before you and tipped up to your eyes, whatever the place.
        val low = head.t + ahead * BAR_M - Vector3(0f, BAR_BELOW_M, 0f)
        bar = Entity.createPanelEntity(R.id.lumiere_bar, Transform(Pose(low, Quaternion.fromDirection((low - head.t).normalize()))))
        FilmBar.wake()
        if (keepWindow) return
        // The window: hidden, but for a question the player asks, just above the bar.
        val w = window() ?: return
        val menus = head.t + ahead * MENU_M - Vector3(0f, MENU_BELOW_M, 0f)
        w.setComponent(Transform(Pose(menus, Quaternion.fromDirection((menus - head.t).normalize()))))
        w.setComponent(Scale(Vector3(MENU_SCALE)))
        w.setComponent(Visible(false))
        windowShown = false
    }

    /**
     * The screen's shape and place for [request]: on its wall (read from
     * Space Setup, the first time asked), pinned where you put it, or
     * floating ahead. Null while the walls are still being read; the screen
     * is made when they arrive.
     */
    private fun placed(request: Theater.Request, eye: Vector3, ahead: Vector3): Pair<TheaterGeometry.Spec, Pose>? {
        val where = place.where
        if (where != Place.ROOM) {
            val spec = where.screen(request.width, request.height, place.size).let { if (where.drawn == null) TheaterGeometry.seated(it, place.seat) else it }
            return spec to Pose(eye + ahead * spec.distanceM + Vector3(0f, spec.aboveEyesM, 0f), Quaternion.fromDirection(ahead))
        }
        val m = place.mount.takeIf { WALL_MOUNT }
        if (m?.wall != null && walls != null) {
            if (walls.state != RoomWalls.State.READY) {
                // Asked once: each tick while the room is read used to add another waiter.
                if (walls.state == RoomWalls.State.LOADING) return null
                walls.load { if (it == RoomWalls.State.READY) remake = true else floatAgain("Your wall couldn't be read, so the screen floats") }
                return null
            }
            val wall = walls.wall(m.wall) ?: run { floatAgain("That wall is gone from Space Setup, so the screen floats"); return null }
            val aspect = request.width.toFloat() / request.height.coerceAtLeast(1)
            val distance = WallMount.distance(wall, eye)
            // TV Mode: the size in inches, as large as the wall holds.
            val holds = minOf(wall.width - 2 * WallMount.MARGIN, (wall.height - 2 * WallMount.MARGIN) * aspect)
            val (width, cut) = TvMode.fitted(place.tvSize, holds)
            if (cut && place.tvSize != toldCut) { toldCut = place.tvSize
                say("This wall holds up to ${TvMode.largestFitting(holds)?.let { "$it″" } ?: "a smaller screen"}", "The screen is as large as the wall allows") }
            val spec = TheaterGeometry.sized(width, request.width, request.height, distance)
            val (x, y) = WallMount.fit(wall, m.x, m.y, spec.widthM, spec.heightM)
            return spec to WallMount.pose(wall, x, y, eye)
        }
        if (m != null) {
            val spec = TheaterGeometry.sized(TvMode.widthM(TvMode.INCHES[place.tvSize]), request.width, request.height, ScreenPlace.PIN_DISTANCE_M)
            return spec to ScreenPlace.pinnedPose(m)
        }
        val spec = TheaterGeometry.seated(TheaterGeometry.room(request.width, request.height, place.size), place.seat)
        return spec to Pose(eye + ahead * spec.distanceM + Vector3(0f, spec.aboveEyesM, 0f), Quaternion.fromDirection(ahead))
    }

    /** The player's More menu, while a film plays: the screen's size, and your wall. */
    private fun menu(): List<Entry> = listOf(
        Theater.request.let { req ->
            val id = req?.itemId.orEmpty()
            val chosen = place.formatFor(id)
            val guessed = req?.let { StereoDetect.of(it.name, it.width, it.height) } ?: StereoDetect.Format.FLAT
            Entry.Link("3D", chosen?.label ?: "Auto (${guessed.label})") {
                listOf(Entry.Choice("Auto (${guessed.label})", chosen == null) { place.setFormat(id, null); remake = true }) +
                    StereoDetect.Format.entries.map { f -> Entry.Choice(f.label, f == chosen) { place.setFormat(id, f); remake = true } }
            }
        },
        Entry.Action("Choose a Place… (${place.where.label})") { PlacePicker.open = true },
    )

    /**
     * The screen onto the wall before you, where your gaze meets it — read
     * from Space Setup, asking for the headset's spatial data the first time.
     * With no wall to be had, it's pinned in the air where you look, so the
     * button always does something, and you're told why.
     */
    private fun hang() {
        fun pinHere(why: String) {
            val head = scene.getViewerPose()
            val ahead = level(head.forward())
            val at = head.t + ahead * ScreenPlace.PIN_DISTANCE_M
            place.mount = ScreenPlace.Mount(null, 0f, 0f, Vector3(at.x, head.t.y, at.z), kotlin.math.atan2(ahead.x, ahead.z))
            remake = true
            say("Pinned where you're looking", why)
        }
        val w = walls ?: return pinHere("This headset's room data isn't available")
        say("Reading your room's walls…")
        w.load { state ->
            when (state) {
                RoomWalls.State.READY -> {
                    val head = scene.getViewerPose()
                    val hit = WallMount.facing(w.walls(), head.t, head.forward().normalize())
                    if (hit == null) pinHere(if (w.walls().isEmpty()) "Space Setup has no walls" else "None of your walls is in front of you")
                    else {
                        place.mount = ScreenPlace.Mount(hit.first.id, hit.second.first, hit.second.second)
                        remake = true
                        say("TV Mode", "On your wall at ${TvMode.NAMES[place.tvSize]}: films in your room play here now")
                    }
                }
                RoomWalls.State.NO_PERMISSION -> pinHere("Allow spatial data for your real walls")
                RoomWalls.State.NO_ROOM -> pinHere("Run Space Setup in the headset's Settings › Physical space")
                else -> pinHere("Your room's walls couldn't be read")
            }
        }
    }

    private fun floatAgain(why: String) {
        place.mount = null
        remake = true
        say(why)
    }

    private fun say(title: String, detail: String? = null) = app.lumiere.android.ui.Notice.show(title, detail)

    private fun showWindow(show: Boolean) {
        if (show == windowShown) return
        windowShown = show
        window()?.setComponent(Visible(show))
    }

    private fun clearScreen() {
        if (screen == null && made == null) return
        Theater.surface = null
        captions?.let { runCatching { it.destroy() } }
        bar?.let { runCatching { it.destroy() } }
        bar = null
        screen?.let { runCatching { it.destroy() } }
        captions = null; screen = null; made = null; current = null
    }

    /** The film over: its bar's menu shut; the window stays hidden, as the theater is closing. */
    private fun restoreWindow() {
        BarMenu.close()
    }

    /** Recentred on you: a floating screen comes back before you (one on your wall stays there). */
    fun recenter() {
        if (made != null && (place.mount == null || !WALL_MOUNT)) remake = true
    }

    private var lastHead: Pose? = null
    /** The size whose "wall holds up to" was said, so it's said once. */
    private var toldCut = -1

    /**
     * Reset View, however it came: the headset's own (holding the Meta button)
     * moves where "ahead" is all at once, which no head turns in a tenth of a
     * second — so a jump that size is taken as a reset, and the screen and its
     * bar come back before you. The SDK's own recenter call isn't relied on alone.
     */
    private fun watchForReset() {
        val head = scene.getViewerPose()
        val was = lastHead
        lastHead = head
        if (was != null && ResetWatch.isReset(was.t, level(was.forward()), head.t, level(head.forward()))) recenter()
    }

    companion object {
        /** Hang on Your Wall, on the transport bar (M4: walls read from their own pose, RoomWalls). */
        const val WALL_MOUNT = true

        /** Where to Watch: this far before you, this far under your eyes. */
        const val PICKER_M = 1.3f
        const val PICKER_BELOW_M = 0.15f

        /** The film's bar: this far before you, this far under your eyes. */
        const val BAR_M = 0.8f
        const val BAR_BELOW_M = 0.36f

        /** A menu during a film, in the window: just above the bar, at this size. */
        const val MENU_M = 0.95f
        const val MENU_BELOW_M = 0.12f
        const val MENU_SCALE = 0.42f

        /** The screen being made, for the panels' settings, which the SDK asks for as it makes them. */
        @Volatile var current: TheaterGeometry.Spec? = null

        /** The kind of picture being shown, for the screen's shape and how its eyes are laid out. */
        @Volatile var currentFormat: StereoDetect.Format = StereoDetect.Format.FLAT

        /** Captions in 180° and 360°: before you, this far, this far under your eyes. */
        const val SPHERE_CAPTIONS_M = 2.5f
        const val SPHERE_CAPTIONS_BELOW_M = 0.55f
    }
}
