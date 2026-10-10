package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.player.PictureInPicture
import app.lumiere.android.player.Theater
import app.lumiere.android.ui.Ambient
import app.lumiere.android.ui.Floating
import app.lumiere.android.ui.PosterWall
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Lut
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.Visible
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Everything Lumiere puts round you on a Quest, looked at four times a
 * second (more while something moves). Browsing, the window and tab bar are
 * yours to carry and resize, in your room. Watching, the film moves to the
 * Theater — its own screen, in the place you chose (your room dimmed, a
 * stadium cinema, the dark) — with the transport near your hands and the
 * window out of the way until you ask for it. Holding the Meta button brings
 * it all back in front of you.
 */
class Director(
    private val scene: Scene,
    private val window: Entity, private val sidebar: Entity, private val ornament: Entity,
    private val wall: Entity, private val transport: Entity,
) {
    private val screen = TheaterScreen()
    private val theatreMade = lazy { Theatre() }
    private val theatre by theatreMade

    // What's up now, so each change is made once.
    private var theaterOn = false
    private var seat: TheaterScreen.Seat? = null
    private var shownPlace: Pair<Stage.Place, Boolean>? = null
    private var windowMode = WindowMode.HOME
    private var windowHome: Pose? = null
    private var sidebarShown = true
    private var ornamentShown = false
    private var wallShown = false
    private var transportShown = false
    private var seenAsks = Stage.bringHereAsks
    private var tilted = false

    // Light: the room's passthrough, or the cinema's hall.
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    private var displayRate = 0f
    private val usualRate by lazy { runCatching { scene.getConfirmedFrameRate() }.getOrDefault(0f) }

    private enum class WindowMode { HOME, ASKED, HIDDEN }

    /** The film's sound comes from here: the Theater's flat screen, the window, or (in a sphere) all round. */
    fun soundSource(): Entity? = when {
        !theaterOn -> window
        Theater.request?.projection != Projection.FLAT -> null
        else -> screen.entity
    }

    fun start(scope: CoroutineScope): Job = scope.launch {
        while (isActive) {
            // A failure here costs a quarter-second, never the app.
            val moving = runCatching { tick() }.onFailure { android.util.Log.w("Lumiere", "director", it) }.getOrDefault(false)
            delay(if (moving) 40 else 250)
        }
    }

    /** One look at the state; true while something is still moving. */
    private fun tick(): Boolean {
        val now = Theater.clockMs()
        val inPlayer = OpenApp.state?.top is Screen.Player
        val playing = PictureInPicture.playing
        if (Stage.bringHereAsks != seenAsks) { seenAsks = Stage.bringHereAsks; recenter() }

        // The Theater: up for a film, down after it.
        val request = Theater.request
        val on = request != null
        if (on != theaterOn) { theaterOn = on; if (on) enterTheater() else leaveTheater() }
        val sphere = on && request!!.projection != Projection.FLAT
        val place = if (on) Stage.place else Stage.Place.ROOM
        if (on) {
            val spec = TheaterGeometry.spec(request!!, place, Stage.screenSize, Stage.curved)
            val s = seat ?: seatHere().also { seat = it }
            if (screen.follow(spec, s, movable = place != Stage.Place.CINEMA)) {
                if (place == Stage.Place.CINEMA && !sphere && !s.tilted)
                    theatre.build(s.floor, spec.widthM, spec.heightM, s.eye.y + spec.aboveEyesM, spec.distanceM)
                shownPlace = null
            }
        }

        // Where you are: passthrough, the cinema's hall, or the dark.
        val hall = on && place == Stage.Place.CINEMA && !sphere && seat?.tilted != true
        if (shownPlace != place to hall) {
            shownPlace = place to hall
            scene.enablePassthrough(!on || (place == Stage.Place.ROOM && !sphere))
            if (theatreMade.isInitialized() || hall) theatre.show(hall)
            shownBrightness = -1f; shownTint = null
        }

        // The window: home while browsing; out of the way in the Theater unless asked for; aside for the wall.
        val wallWanted = PosterWall.open && !on
        val mode = when {
            on && Theater.windowAsked -> WindowMode.ASKED
            on || wallWanted -> WindowMode.HIDDEN
            else -> WindowMode.HOME
        }
        if (mode != windowMode) setWindow(mode)

        // The tab bar: there while browsing; the transport has the Theater's controls.
        val showSidebar = !on
        if (showSidebar != sidebarShown) { sidebarShown = showSidebar; show(sidebar, showSidebar) }

        // The poster wall round you.
        if (wallWanted != wallShown) {
            wallShown = wallWanted
            if (wallWanted) placeWall() else wall.setComponent(Transform(Window.parked()))
            wall.setComponent(Visible(wallWanted))
        }

        // The transport: while paused or the window's asked for, or for a few seconds after you touch anything.
        val showTransport = on && Theater.transportShows(playing && mode != WindowMode.ASKED, now)
        if (showTransport != transportShown) {
            transportShown = showTransport
            if (showTransport) placeTransport() else transport.setComponent(Transform(Window.parked()))
            transport.setComponent(Visible(showTransport))
        }

        // The ornament (Up Next, the scrub frames, the song): where you look each time it appears.
        val showOrnament = Floating.showing
        if (showOrnament != ornamentShown) {
            ornamentShown = showOrnament
            if (showOrnament) placeOrnament() else ornament.setComponent(Transform(Window.parked()))
            ornament.setComponent(Visible(showOrnament))
        }

        // The display at the film's own rate (24 fps at 72 Hz); the headset's own otherwise.
        matchDisplay(if (on || inPlayer) Display.rateFor(PictureInPicture.frameRate) else 0f)

        // The sleep timer: the light fades over its last minute, then the film stops.
        val sleepLeft = if (Stage.sleepAt == 0L) Long.MAX_VALUE else Stage.sleepAt - System.currentTimeMillis()
        if (sleepLeft <= 0) { PictureInPicture.pause(); Stage.sleepDone() }
        val watching = on || inPlayer
        val target = if (watching && sleepLeft < 60_000) CinemaLight.PLAYING * (sleepLeft.coerceAtLeast(0) / 60_000f)
            else CinemaLight.target(watching, playing)
        brightness = if (app.lumiere.android.Motion.reduced) target else CinemaLight.ease(brightness, target)
        val tint = Ambient.colour?.let { Triple(it.red, it.green, it.blue) }
        when {
            hall -> theatre.light(brightness, tint)
            !on || (place == Stage.Place.ROOM && !sphere) -> lightRoom(brightness, tint)
        }
        return brightness != target
    }

    /** A film starts: you're seated where you are, the window steps aside. */
    private fun enterTheater() {
        seat = seatHere()
        Theater.poke()
    }

    /** The film ends: the screen goes, the window comes back where it was. */
    private fun leaveTheater() {
        screen.clear()
        if (theatreMade.isInitialized()) theatre.show(false)
        seat = null
        shownPlace = null
    }

    /** Your eyes and the way you face now: level, or tilted with you when you lie back and look up. */
    private fun seatHere(): TheaterScreen.Seat {
        val head = scene.getViewerPose()
        val look = head.forward().normalize()
        if (Display.lookingUp(look.y)) return TheaterScreen.Seat(head.t, Quaternion.fromDirection(look), tilted = true)
        return TheaterScreen.Seat(head.t, head.removePitchAndRoll().q, tilted = false)
    }

    private fun setWindow(mode: WindowMode) {
        if (windowMode == WindowMode.HOME) windowHome = window.getComponent<Transform>().transform
        windowMode = mode
        when (mode) {
            WindowMode.HOME -> { windowHome?.let { window.setComponent(Transform(it)) }; show(window, true) }
            WindowMode.ASKED -> {
                val head = scene.getViewerPose()
                val ahead = head.removePitchAndRoll()
                // A little high, so the transport below stays clear of it.
                val at = head.t + flat(ahead.forward()) * Window.ASKED_WINDOW_DISTANCE_M
                window.setComponent(Transform(Pose(Vector3(at.x, head.t.y + 0.15f, at.z), ahead.q)))
                show(window, true)
            }
            WindowMode.HIDDEN -> { window.setComponent(Transform(Window.parked())); show(window, false) }
        }
    }

    private fun show(e: Entity, on: Boolean) = e.setComponent(Visible(on))

    /**
     * Everything back in front of you, as holding the Meta button does in any
     * Quest app: in the Theater you're seated again where you are now, the
     * screen (and hall) before you; browsing, the window comes before you
     * with the tab bar docked beside it; the wall and the panels follow.
     */
    fun recenter() {
        if (theaterOn) {
            val s = seatHere().also { seat = it }
            screen.place(s)
            TheaterScreen.current?.let { spec ->
                if (Stage.place == Stage.Place.CINEMA && spec.projection == Projection.FLAT && !s.tilted)
                    theatre.build(s.floor, spec.widthM, spec.heightM, s.eye.y + spec.aboveEyesM, spec.distanceM)
            }
            if (windowMode == WindowMode.ASKED) setWindow(WindowMode.ASKED)
            if (transportShown) placeTransport()
        } else {
            windowInFront()
            if (windowMode != WindowMode.HOME) windowHome = window.getComponent<Transform>().transform
            else dockSidebar()
        }
        if (wallShown) placeWall()
        if (ornamentShown) placeOrnament()
    }

    /** The window before your eyes, facing you; looking up while lying back, where you look. */
    private fun windowInFront() {
        val head = scene.getViewerPose()
        val look = head.forward().normalize()
        tilted = Display.lookingUp(look.y)
        if (tilted) {
            window.setComponent(Transform(Pose(head.t + look * Window.DISTANCE_M, Quaternion.fromDirection(look))))
            return
        }
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.DISTANCE_M
        window.setComponent(Transform(Pose(Vector3(at.x, head.t.y - 0.1f, at.z), ahead.q)))
    }

    /** The tab bar docked beside the window's left edge; from there it's yours to move. */
    private fun dockSidebar() {
        sidebar.setComponent(Transform(Docking.beside(window.getComponent<Transform>().transform, Window.WIDTH_M)))
    }

    /** The wall's middle before you, its curve centred on you, a little above your eyes. */
    private fun placeWall() {
        val head = scene.getViewerPose()
        val ahead = head.removePitchAndRoll()
        val at = head.t + flat(ahead.forward()) * Window.WALL_RADIUS_M
        wall.setComponent(Transform(Pose(Vector3(at.x, head.t.y + Window.WALL_ABOVE_EYES_M, at.z), ahead.q)))
    }

    /** The transport near your hands, below your line of sight to the screen, turned up to your eyes. */
    private fun placeTransport() {
        transport.setComponent(Transform(nearYou(Window.TRANSPORT_DISTANCE_M, Window.TRANSPORT_BELOW_EYES_M)))
    }

    /** The ornament before you; over the transport while the Theater is up. */
    private fun placeOrnament() {
        val below = if (theaterOn) Window.ORNAMENT_OVER_TRANSPORT_BELOW_EYES_M else Window.ORNAMENT_BELOW_EYES_M
        ornament.setComponent(Transform(nearYou(Window.ORNAMENT_DISTANCE_M, below)))
    }

    /** A panel [distance] before you and [below] your eyes, facing your eyes (tilted with you lying back). */
    private fun nearYou(distance: Float, below: Float): Pose {
        val head = scene.getViewerPose()
        val look = head.forward().normalize()
        val facing = if (Display.lookingUp(look.y)) Quaternion.fromDirection(look) else head.removePitchAndRoll().q
        val at = head.t + facing * Vector3(0f, -below, distance)
        return Pose(at, Quaternion.fromDirection((at - head.t).normalize()))
    }

    private fun flat(v: Vector3): Vector3 = Vector3(v.x, 0f, v.z).let { if (it.length() < 1e-3f) Vector3(0f, 0f, 1f) else it.normalize() }

    /** The headset's display at [rate] for a film (0: its usual rate again). */
    private fun matchDisplay(rate: Float) {
        val wanted = if (rate > 0f) rate else usualRate
        if (wanted <= 0f || wanted == displayRate) return
        displayRate = wanted
        if (!scene.requestExactDisplayRate(wanted)) scene.setPreferredDisplayRate(wanted)
    }

    /** Your room's passthrough at [level], with the film's colour spilling in as it darkens. */
    private fun lightRoom(level: Float, tint: Triple<Float, Float, Float>?) {
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
