package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.Stage
import app.lumiere.android.player.PictureInPicture
import app.lumiere.android.ui.Ambient
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Lut
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Grabbable
import com.meta.spatial.toolkit.GrabbableType
import com.meta.spatial.toolkit.Scale
import com.meta.spatial.toolkit.Transform
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
 * cinema, passthrough gives way to a dark theatre and the window becomes an
 * eight-metre screen before your chosen row, whose floor catches the film's
 * colour. Four looks a second; light and size change only while they move.
 */
class Cinema(private val scene: Scene, private val window: Entity, private val sidebar: Entity) {
    // Built the first time the cinema opens, not at start: the room never needs it.
    private val theatreMade = lazy { Theatre() }
    private val theatre by theatreMade
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    private var size = Seats.roomScale(Stage.roomSize)
    private var place: Stage.Place? = null
    private var roomPose: Pose? = null
    private var seenAsks = Stage.bringHereAsks
    private var seat = -1
    private var grabbable: Boolean? = null
    private var sidebarShown = true
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

            val wanted = if (cinema) Seats.CINEMA_SCALE else Seats.roomScale(Stage.roomSize)
            size = if (reduced) wanted else CinemaLight.ease(size, wanted)
            window.setComponent(Scale(Vector3(size)))
            grab(!cinema && !Stage.locked, if (tilted) GrabbableType.FACE else GrabbableType.PIVOT_Y)
            // Out of the way while a film plays; back the moment it pauses.
            val showSidebar = !(inPlayer && playing)
            if (showSidebar != sidebarShown) { sidebarShown = showSidebar; sidebar.setComponent(Visible(showSidebar)) }
            return !(brightness == target && size == wanted)
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
            return
        }
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.DISTANCE_M
        window.setComponent(Transform(Pose(Vector3(at.x, head.t.y - 0.1f, at.z), ahead.q)))
    }

    private fun seatAt(row: Int) {
        seat = row
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Seats.rowDistance(row)
        val screen = Pose(Vector3(at.x, Seats.screenMiddleY(head.t.y, Window.HEIGHT_M * Seats.CINEMA_SCALE), at.z), ahead.q)
        window.setComponent(Transform(screen))
        theatre.place(screen, Window.HEIGHT_M * Seats.CINEMA_SCALE)
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
