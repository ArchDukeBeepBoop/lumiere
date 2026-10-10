package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.Stage
import app.lumiere.android.player.PictureInPicture
import app.lumiere.android.ui.Ambient
import app.lumiere.android.ui.Floating
import app.lumiere.android.ui.PosterWall
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Lut
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.PanelSceneObject
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Grabbable
import com.meta.spatial.toolkit.GrabbableType
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.TransformParent
import com.meta.spatial.toolkit.Visible
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The screen and the light around it, following the sidebar's choices
 * (Stage) and the film. In your room the window keeps the place you carried
 * it to, at the size you chose, and the lights go down for a film. In the
 * cinema, passthrough gives way to a dark theatre and the window becomes a
 * screen nearly five metres wide before your chosen row, whose floor
 * catches the film's colour, with the sidebar brought to your side. Four
 * looks a second; light changes only while it moves.
 */
class Cinema(
    private val scene: Scene, private val window: Entity, private val sidebar: Entity, private val ornament: Entity,
    private val wall: Entity,
    /** The panel behind an entity, once the SDK has made it; null until then. */
    private val panelOf: (Entity) -> PanelSceneObject?,
) {
    private val sphere = SurroundSphere(scene)
    private var surroundShown = false
    private var wallShown = false
    /** Where the window was when the wall came up, to put it back. */
    private var beforeWall: Pose? = null
    private var windowShown = true

    // Built the first time the cinema opens, not at start: the room never needs it.
    private val theatreMade = lazy { Theatre() }
    private val theatre by theatreMade
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    /** The window's shape as last made: at first, as LumiereSpace registered it, so a start at the usual size reshapes nothing. */
    private var shownShape: Seats.Shape? = Seats.room(Seats.ROOM.size / 2, curved = true)
    private var sidebarNear = false
    private var lockedSeen = Stage.locked
    private var place: Stage.Place? = null
    private var roomPose: Pose? = null
    private var seenAsks = Stage.bringHereAsks
    private var seat = -1
    private var grabbable: Boolean? = null
    private var sidebarShown = true
    private var ornamentShown = false
    private var tilted = false
    private var displayRate = 0f
    private val usualRate by lazy { runCatching { scene.getConfirmedFrameRate() }.getOrDefault(0f) }

    fun start(scope: CoroutineScope): Job = scope.launch {
        while (isActive) {
            // A failure here costs the cinema a quarter-second, never the app.
            val moving = runCatching { tick() }.onFailure { android.util.Log.w("Lumiere", "cinema tick", it) }.getOrDefault(false)
            delay(if (moving) 40 else 250)
        }
    }

    /** One look at the state; true while something is still moving. */
    private fun tick(): Boolean {
        run {
            val inPlayer = OpenApp.state?.top is Screen.Player
            val playing = PictureInPicture.playing
            val reduced = app.lumiere.android.Motion.reduced
            if (Stage.place != place) enter(Stage.place)
            if (Stage.bringHereAsks != seenAsks) { seenAsks = Stage.bringHereAsks; bringHere() }
            val cinema = place == Stage.Place.CINEMA
            if (cinema && Stage.seat != seat) seatAt(Stage.seat)
            // A 180° or 360° film: the sphere round you instead of the room or the theatre.
            val surround = sphere.follow()
            if (surround != surroundShown) {
                surroundShown = surround
                scene.enablePassthrough(!surround && !cinema)
                if (cinema) theatre.show(!surround)
                shownBrightness = -1f
            }
            // The poster wall comes up round you; the window steps aside until it goes.
            val showWall = PosterWall.open && !surround
            if (showWall != wallShown) {
                wallShown = showWall
                if (showWall) {
                    beforeWall = window.getComponent<Transform>().transform
                    placeWall()
                    window.setComponent(Transform(Window.parked()))
                } else {
                    wall.setComponent(Transform(Window.parked()))
                    beforeWall?.let { window.setComponent(Transform(it)) }
                    beforeWall = null
                }
                wall.setComponent(Visible(showWall))
            }
            // In the sphere, the window steps away while the film plays and is back the moment it pauses.
            val showWindow = !(surround && playing) && !showWall
            if (showWindow != windowShown) { windowShown = showWindow; window.setComponent(Visible(showWindow)) }

            matchDisplay(if (inPlayer) Display.rateFor(PictureInPicture.frameRate) else 0f)
            // The sleep timer: the room fades over its last minute, then the film stops.
            val sleepLeft = if (Stage.sleepAt == 0L) Long.MAX_VALUE else Stage.sleepAt - System.currentTimeMillis()
            if (sleepLeft <= 0) { PictureInPicture.pause(); Stage.sleepDone() }
            val fading = inPlayer && sleepLeft < 60_000
            val target = if (fading) CinemaLight.PLAYING * (sleepLeft.coerceAtLeast(0) / 60_000f)
                else CinemaLight.target(inPlayer, playing)
            brightness = if (reduced) target else CinemaLight.ease(brightness, target)
            val tint = Ambient.colour?.let { Triple(it.red, it.green, it.blue) }
            if (cinema) theatre.light(brightness, tint) else light(brightness, tint)

            // The screen's real size and curve; the sidebar follows its edge, or comes to you in the cinema.
            val shape = if (cinema) Seats.cinema(Stage.seat, Stage.curved) else Seats.room(Stage.roomSize, Stage.curved)
            if (shape != shownShape && resize(window, shape)) {
                shownShape = shape
                if (cinema) seatAt(Stage.seat)
                placeSidebar(cinema)
                settle()
            }
            // Anchored: the spot is remembered, and given back at the next start (LumiereSpace).
            if (Stage.locked != lockedSeen) { lockedSeen = Stage.locked; if (Stage.locked) rememberAnchor() }
            grab(!cinema && !Stage.locked, if (tilted) GrabbableType.FACE else GrabbableType.PIVOT_Y)
            // Out of the way while a film plays; back the moment it pauses.
            val showSidebar = !(inPlayer && playing)
            if (showSidebar != sidebarShown) { sidebarShown = showSidebar; sidebar.setComponent(Visible(showSidebar)) }
            // The ornament comes to where you're looking each time it appears, then stays put.
            val showOrnament = Floating.showing
            if (showOrnament != ornamentShown) {
                ornamentShown = showOrnament
                // Hidden is also put out of reach: a hidden panel may still catch the pointer.
                if (showOrnament) placeOrnament() else ornament.setComponent(Transform(Window.parked()))
                ornament.setComponent(Visible(showOrnament))
            }
            return brightness != target
        }
    }

    private fun enter(next: Stage.Place) {
        val from = place
        place = next
        if (next == Stage.Place.CINEMA) {
            if (from == Stage.Place.ROOM || from == null) roomPose = window.getComponent<Transform>().transform
            scene.enablePassthrough(false)
            theatre.show(true)
            seat = -1
        } else {
            if (theatreMade.isInitialized()) theatre.show(false)
            scene.enablePassthrough(true)
            shownBrightness = -1f
            roomPose?.let { window.setComponent(Transform(it)) }
        }
        // A new shape for a new place, and the sidebar with it (at the start, only if it differs).
        if (from != null) shownShape = null
    }

    /** Before your eyes, facing you: the room's window, or the cinema's screen from your row. */
    private fun bringHere() {
        if (place == Stage.Place.CINEMA) { seat = -1; seatAt(Stage.seat); return }
        val head = scene.getViewerPose()
        val look = head.forward().normalize()
        // Lying down and looking up: the screen goes where you look, tilted to face you.
        tilted = Display.lookingUp(look.y)
        if (tilted) {
            val at = head.t + look * Window.DISTANCE_M
            window.setComponent(Transform(Pose(at, com.meta.spatial.core.Quaternion.fromDirection(look))))
            if (Stage.locked) rememberAnchor()
            return
        }
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.DISTANCE_M
        window.setComponent(Transform(Pose(Vector3(at.x, head.t.y - 0.1f, at.z), ahead.q)))
        if (Stage.locked) rememberAnchor()
    }

    /** The wall's middle before you, its curve centred on you, a little above your eyes. */
    private fun placeWall() {
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.WALL_RADIUS_M
        wall.setComponent(Transform(Pose(Vector3(at.x, head.t.y + Window.WALL_ABOVE_EYES_M, at.z), ahead.q)))
    }

    /** Before you and a little below your eyes, facing you; tilted with you when you're lying back. */
    private fun placeOrnament() {
        val head = scene.getViewerPose()
        val look = head.forward().normalize()
        if (Display.lookingUp(look.y)) {
            val q = com.meta.spatial.core.Quaternion.fromDirection(look)
            val down = q * Vector3(0f, -1f, 0f)
            ornament.setComponent(Transform(Pose(head.t + look * Window.ORNAMENT_DISTANCE_M + down * Window.ORNAMENT_BELOW_EYES_M, q)))
            return
        }
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.ORNAMENT_DISTANCE_M
        ornament.setComponent(Transform(Pose(Vector3(at.x, head.t.y - Window.ORNAMENT_BELOW_EYES_M, at.z), ahead.q)))
    }

    private fun seatAt(row: Int) {
        seat = row
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val shape = Seats.cinema(row, Stage.curved)
        val at = head.t + flat(ahead.forward()) * Seats.rowDistance(row)
        val screen = Pose(Vector3(at.x, Seats.screenMiddleY(head.t.y, shape.heightM), at.z), ahead.q)
        window.setComponent(Transform(screen))
        theatre.place(screen, shape.widthM)
        seatPose = Pose(head.t, ahead.q)
        if (sidebarNear) placeSidebar(cinema = true)
    }

    /** Where you sat down in the cinema, facing the screen; the sidebar is placed from it. */
    private var seatPose: Pose? = null

    /**
     * The panel made [shape] for real: its width, height and curve in
     * metres, the picture inside it unchanged (Lumiere keeps laying out in
     * the same 1280 × 800). PanelSceneObject.reshape rebuilds only the
     * surface it is shown on; the app inside keeps running. False until the
     * panel exists.
     */
    private fun resize(entity: Entity, shape: Seats.Shape): Boolean {
        val panel = panelOf(entity) ?: return false
        val config = panel.getPanelShapeConfig() ?: return false
        config.width = shape.widthM
        config.height = shape.heightM
        config.radiusForCylinderOrSphere = shape.radiusM
        // Tried once per shape: a failure is logged, not repeated four times a second.
        runCatching { panel.reshape(config) }.onFailure { android.util.Log.e("Lumiere", "reshape to $shape", it) }
        return true
    }

    /**
     * The sidebar: in your room, carried on along the screen's curve just
     * past its left edge, turned to you, and moving with it; in the cinema,
     * where a remote would be — by your left hand, within reach, since the
     * screen is metres away.
     */
    private fun placeSidebar(cinema: Boolean) {
        if (cinema) {
            val seat = seatPose ?: return
            if (!sidebarNear) { sidebarNear = true; sidebar.tryRemoveComponent<TransformParent>() }
            val left = flat(seat.q * Vector3(1f, 0f, 0f))
            val forward = flat(seat.q * Vector3(0f, 0f, 1f))
            val turn = Math.toRadians(Window.NEAR_SIDEBAR_ANGLE_DEG.toDouble())
            val at = seat.t + forward * (Window.NEAR_SIDEBAR_DISTANCE_M * kotlin.math.cos(turn).toFloat()) +
                left * (Window.NEAR_SIDEBAR_DISTANCE_M * kotlin.math.sin(turn).toFloat()) -
                Vector3(0f, Window.NEAR_SIDEBAR_BELOW_EYES_M, 0f)
            sidebar.setComponent(Transform(Pose(at, com.meta.spatial.core.Quaternion.fromDirection(flat(at - seat.t)))))
            return
        }
        val shape = shownShape ?: Seats.room(Stage.roomSize, Stage.curved)
        val (x, z, dx, dz) = Seats.sidebarBeside(shape)
        sidebarNear = false
        sidebar.setComponent(TransformParent(window))
        sidebar.setComponent(Transform(Pose(Vector3(x, 0f, z), com.meta.spatial.core.Quaternion.fromDirection(Vector3(dx, 0f, dz)))))
    }

    /** The screen's spot written to Stage, to be given back at the next start. */
    private fun rememberAnchor() {
        val p = window.getComponent<Transform>().transform
        Stage.rememberAnchor(floatArrayOf(p.t.x, p.t.y, p.t.z, p.q.w, p.q.x, p.q.y, p.q.z))
    }

    /**
     * After a resize: the window's place written again, unchanged. Meta's
     * pointer (ISDK) re-reads a panel's size and curve when its Transform or
     * panel data change, so this makes the pointer aim at the new shape at
     * once (IsdkComponentExtensions.updateIsdkComponentProperties).
     */
    private fun settle() {
        window.setComponent(Transform(window.getComponent<Transform>().transform))
    }

    private fun flat(v: Vector3): Vector3 = Vector3(v.x, 0f, v.z).let { if (it.length() < 1e-3f) Vector3(0f, 0f, 1f) else it.normalize() }

    private var grabType: GrabbableType? = null

    /** Movable or pinned; a tilted screen keeps facing you as it's carried, an upright one stays upright. */
    private fun grab(on: Boolean, type: GrabbableType) {
        if (grabbable == on && grabType == type) return
        grabbable = on; grabType = type
        window.setComponent(Grabbable(enabled = on, type = type, minHeight = Window.MIN_HEIGHT_M, maxHeight = if (type == GrabbableType.FACE) 4f else Window.MAX_HEIGHT_M))
    }

    /** The headset's display at [rate] for a film (0: its usual rate again). */
    private fun matchDisplay(rate: Float) {
        val wanted = if (rate > 0f) rate else usualRate
        if (wanted <= 0f || wanted == displayRate) return
        displayRate = wanted
        if (!scene.requestExactDisplayRate(wanted)) scene.setPreferredDisplayRate(wanted)
    }

    private fun light(level: Float, tint: Triple<Float, Float, Float>?) {
        if (level == shownBrightness && tint == shownTint) return
        shownBrightness = level; shownTint = tint
        val (r, g, b) = tint ?: Triple(0f, 0f, 0f)
        val table = Lut()
        for (x in 0..15) for (y in 0..15) for (z in 0..15) {
            table.setMapping(x, y, z, CinemaLight.channel(x, level, r), CinemaLight.channel(y, level, g), CinemaLight.channel(z, level, b))
        }
        runCatching { scene.setPassthroughLUT(table) }
    }
}
