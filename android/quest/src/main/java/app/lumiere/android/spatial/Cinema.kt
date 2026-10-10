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
    private val theatre by lazy { Theatre() }
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

            val target = CinemaLight.target(inPlayer, playing)
            brightness = if (reduced) target else CinemaLight.ease(brightness, target)
            val tint = Ambient.colour?.let { Triple(it.red, it.green, it.blue) }
            if (cinema) theatre.light(brightness, tint) else light(brightness, tint)

            val wanted = if (cinema) Seats.CINEMA_SCALE else Seats.roomScale(Stage.roomSize)
            size = if (reduced) wanted else CinemaLight.ease(size, wanted)
            window.setComponent(Scale(Vector3(size)))
            grab(!cinema && !Stage.locked)
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
            theatre.show(false)
            scene.enablePassthrough(true)
            shownBrightness = -1f
            roomPose?.let { window.setComponent(Transform(it)) }
        }
    }

    /** Before your eyes, facing you: the room's window, or the cinema's screen from your row. */
    private fun bringHere() {
        if (place == Stage.Place.CINEMA) { seat = -1; seatAt(Stage.seat); return }
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.DISTANCE_M
        window.setComponent(Transform(Pose(Vector3(at.x, head.t.y - 0.1f, at.z), ahead.q)))
    }

    private fun seatAt(row: Int) {
        seat = row
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Seats.rowDistance(row)
        val screen = Pose(Vector3(at.x, head.t.y + Seats.ABOVE_EYES, at.z), ahead.q)
        window.setComponent(Transform(screen))
        theatre.place(screen, Window.HEIGHT_M * Seats.CINEMA_SCALE)
    }

    private fun flat(v: Vector3): Vector3 = Vector3(v.x, 0f, v.z).let { if (it.length() < 1e-3f) Vector3(0f, 0f, 1f) else it.normalize() }

    private fun grab(on: Boolean) {
        if (grabbable == on) return
        grabbable = on
        window.setComponent(Grabbable(enabled = on, type = GrabbableType.PIVOT_Y, minHeight = Window.MIN_HEIGHT_M, maxHeight = Window.MAX_HEIGHT_M))
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
