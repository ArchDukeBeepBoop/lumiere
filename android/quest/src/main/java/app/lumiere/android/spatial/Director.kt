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
 * stadium cinema, a timber cabin, a pontoon on a lake at dusk, the dark,
 * space) — with the transport near your hands and the
 * window out of the way until you ask for it. Holding the Meta button brings
 * it all back in front of you.
 */
class Director(
    private val scene: Scene,
    private val window: Entity, private val sidebar: Entity, private val ornament: Entity,
    private val wall: Entity, private val transport: Entity,
    /** The place's own sounds; none on a plain start. */
    private val ambience: Ambience? = null,
    /** Your room's walls from Space Setup, for the screen on your wall; none on a plain start. */
    private val walls: RoomWalls? = null,
) {
    private var seenMountAsks = Stage.mountAsks
    /** The room is read for a mount made before at most once a start, and only if already allowed. */
    private var wallsTried = false
    private val screen = TheaterScreen()
    private val marquee = MarqueeScreen()
    private val sky = Sky()
    private val hold = TheaterHold()
    /** The film's screen as shown: the player's request, held through the gaps (TheaterHold). */
    private var shownRequest: Theater.Request? = null
    private val theatreMade = lazy { Theatre() }
    private val theatre by theatreMade
    private val cabinMade = lazy { Scenery(Cabin::colour, Cabin::surface, Cabin::moves) }
    private val cabin by cabinMade
    private val dockMade = lazy { Scenery(Dock::colour, Dock::surface, Dock::moves) }
    private val dock by dockMade
    private val terraceMade = lazy { Scenery(Terrace::colour, Terrace::surface, Terrace::moves) }
    private val terrace by terraceMade
    private val moonMade = lazy { Scenery(MoonBase::colour, MoonBase::surface, MoonBase::moves) }
    private val moonBase by moonMade
    private val stationMade = lazy { Scenery(Station::colour, Station::surface, Station::moves) }
    private val station by stationMade

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
    /** Whether the window was last brought before you for away from your room (low) or for it; null at the start. */
    private var windowAway: Boolean? = null

    // Light: the room's passthrough, or the place round you (the cinema's hall, the cabin, the pontoon).
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    private var displayRate = 0f
    private val usualRate by lazy { runCatching { scene.getConfirmedFrameRate() }.getOrDefault(0f) }

    private enum class WindowMode { HOME, ASKED, HIDDEN }

    private companion object {
        /** Below this, the head isn't tracked yet (or you're lying on the floor): no hall is built round it. */
        const val MIN_EYE_HEIGHT_M = 0.3f
    }

    /** The film's sound comes from here: the Theater's flat screen, the window, or (in a sphere) all round. */
    /**
     * What moves in the place you're in, [seconds] in: the fire and the
     * candles flicker, the fireflies wander. Every frame (Animator); nothing
     * moves for anyone who asked for less motion.
     */
    fun animate(seconds: Float) {
        if (app.lumiere.android.Motion.reduced) return
        if (cabinMade.isInitialized()) cabin.animate(seconds)
        if (dockMade.isInitialized()) dock.animate(seconds)
        if (terraceMade.isInitialized()) terrace.animate(seconds)
        if (moonMade.isInitialized()) moonBase.animate(seconds)
        if (stationMade.isInitialized()) station.animate(seconds)
    }

    fun soundSource(): Entity? = when {
        !theaterOn -> window
        shownRequest?.projection != Projection.FLAT -> null
        else -> screen.entity
    }

    fun start(scope: CoroutineScope): Job = scope.launch {
        // The tab bar's spatial buttons work from now on (a plain start never gets here).
        Stage.directed = true
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
        if (Stage.mountAsks != seenMountAsks) { seenMountAsks = Stage.mountAsks; mountOrUnmount() }

        // The Theater: up for a film, down after it — and not down between episodes.
        val request = hold.request(Theater.request, inPlayer, now).also { shownRequest = it }
        val on = request != null
        if (on != theaterOn) { theaterOn = on; if (on) enterTheater() else leaveTheater() }
        val sphere = on && request!!.projection != Projection.FLAT
        // The place you chose is where you are, browsing as well as watching: choose the cinema
        // and you're in its hall at once, the window before you, the big screen showing the
        // title you're on until a film takes it; the dark and space have the big screen too.
        val place = Stage.place
        val away = place != Stage.Place.ROOM
        // A film starting away from your room: the window steps aside the moment you press Play,
        // the big screen showing the title until the picture comes (or a while, if it never does).
        val waiting = hold.waiting(inPlayer && Theater.controls != null, on, now) && away
        if (!on && away) {
            // Not before the headset knows where your head is (at the very start it may read the floor).
            val s = browseSeat ?: seatHere().takeIf { it.eye.y > MIN_EYE_HEIGHT_M }?.also { browseSeat = it }
            if (s != null) {
                val spec = browseSpec(place)
                surround(place, s, spec)
                marquee.follow(spec, s)
            }
        }
        if (on || !away) marquee.clear()
        if (!away) browseSeat = null
        if (on) {
            val spec = TheaterGeometry.spec(request!!, place, Stage.screenSize, Stage.curved)
            val s = seat ?: seatHere().also { seat = it }
            val hung = if (place == Stage.Place.ROOM && request.projection == Projection.FLAT) onYourWall(request, s) else null
            if (hung != null) { if (screen.follow(hung.first, s, movable = false, on = hung.second)) shownPlace = null }
            else if (screen.follow(spec, s, movable = !TheaterGeometry.fixedScreen(place))) {
                surround(place, s, spec)
                shownPlace = null
            }
        }

        // Where you are: passthrough, the cinema's hall, the cabin, the pontoon, or the dark; a sky.
        val tiltedSeat = (if (on) seat else browseSeat)?.tilted == true
        val seated = !sphere && !tiltedSeat
        val hall = place == Stage.Place.CINEMA && seated
        val inCabin = place == Stage.Place.CABIN && seated
        val onDock = place == Stage.Place.LAKE && seated
        val onTerrace = place == Stage.Place.CLOUDS && seated
        val onMoon = place == Stage.Place.MOON && seated
        val aboard = place == Stage.Place.STATION && seated
        // The place's sound, from where its sources are as you turn; quiet, and gone while a film plays.
        ambience?.let { a ->
            val sounds = if (sphere || (place != Stage.Place.SPACE && !seated)) null else Soundscape.sceneFor(place, hall)
            val from = (if (on) seat else browseSeat)?.facing
            val turned = from?.let { turnedFrom(it, lookingAt()) } ?: 0f
            a.set(sounds, Stage.ambience && !(on && playing), turned)
        }
        if (shownPlace != place to seated) {
            shownPlace = place to seated
            scene.enablePassthrough(place == Stage.Place.ROOM && !sphere)
            if (theatreMade.isInitialized() || hall) theatre.show(hall)
            if (cabinMade.isInitialized() || inCabin) cabin.show(inCabin)
            if (dockMade.isInitialized() || onDock) dock.show(onDock)
            if (terraceMade.isInitialized() || onTerrace) terrace.show(onTerrace)
            if (moonMade.isInitialized() || onMoon) moonBase.show(onMoon)
            if (stationMade.isInitialized() || aboard) station.show(aboard)
            sky.show(if (sphere) null else Sky.pictureFor(place))
            shownBrightness = -1f; shownTint = null
        }

        // The window: home while browsing; out of the way in the Theater unless asked for; aside for the wall.
        val wallWanted = PosterWall.open && !on
        val mode = when {
            on && Theater.windowAsked -> WindowMode.ASKED
            on || wallWanted || waiting -> WindowMode.HIDDEN
            else -> WindowMode.HOME
        }
        if (mode != windowMode) setWindow(mode)
        // Browsing, the window comes before you as the place asks: low away from your room, so the big
        // screen shows above it; as a Quest window in it. Only as you go between the two (and once at the
        // start, away), so wherever you carry it otherwise, it stays.
        if (mode == WindowMode.HOME && windowAway != away) {
            val head = scene.getViewerPose()
            if (head.t.y > MIN_EYE_HEIGHT_M) {
                val first = windowAway == null
                windowAway = away
                if (!first || away) { windowInFront(); dockSidebar() }
            }
        }

        // The tab bar: there while browsing; the transport has the Theater's controls.
        val showSidebar = !on && !waiting
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
        // The colour of the picture now (from its trickplay frames), else the title's own.
        val tint = (Theater.screenColour ?: Ambient.colour)?.let { Triple(it.red, it.green, it.blue) }
        when {
            hall -> theatre.light(brightness, tint)
            inCabin -> cabin.light(brightness, tint)
            onDock -> dock.light(brightness, tint)
            onTerrace -> terrace.light(brightness, tint)
            onMoon -> moonBase.light(brightness, tint)
            aboard -> station.light(brightness, tint)
            place == Stage.Place.ROOM && !sphere -> lightRoom(brightness, tint)
        }
        return brightness != target
    }

    /**
     * The screen on your wall, if you mounted it and the wall is known: its
     * spec (your size, from where you stood, kept on the wall) and pose.
     */
    private fun onYourWall(request: Theater.Request, s: TheaterScreen.Seat): Pair<TheaterGeometry.Spec, Pose>? {
        val m = Stage.mount ?: return null
        val w = walls ?: return null
        if (w.state != RoomWalls.State.READY) {
            if (!wallsTried && w.allowed()) { wallsTried = true; w.load { shownPlace = null } }
            return null
        }
        val wall = w.wall(m.wall) ?: return null
        val aspect = TheaterGeometry.aspectOf(request)
        val width = WallMount.width(wall, TheaterGeometry.SIZE_DEGREES[Stage.screenSize.coerceIn(0, TheaterGeometry.SIZE_DEGREES.lastIndex)], m.distance, aspect)
        val (x, y) = WallMount.fit(wall, m.x, m.y, width, width / aspect)
        return TheaterGeometry.mounted(request, width, m.distance) to WallMount.pose(wall, x, y, s.eye)
    }

    /** The screen onto the wall you face, or off it again; what happened is said over the transport. */
    private fun mountOrUnmount() {
        if (Stage.mount != null) { Stage.mounted(null); Theater.say("The screen floats again"); return }
        val w = walls ?: return Theater.say("Your room's walls can't be read on this start")
        Theater.say("Reading your room's walls…")
        w.load { state ->
            when (state) {
                RoomWalls.State.READY -> {
                    val head = scene.getViewerPose()
                    val hit = WallMount.facing(w.walls(), head.t, head.forward().normalize())
                    if (hit == null) Theater.say("Look at a wall of your room, then choose this again")
                    else {
                        val (wall, at) = hit
                        Stage.mounted(Stage.Mount(wall.id, at.first, at.second, WallMount.distance(wall, head.t)))
                        Theater.say("On your wall: films in your room play here now")
                    }
                }
                RoomWalls.State.NO_PERMISSION -> Theater.say("To use your walls, allow Lumiere spatial data (Settings › Privacy)")
                RoomWalls.State.NO_ROOM -> Theater.say("Set up your space first: Settings › Physical space › Space setup")
                else -> Theater.say("Your room's walls couldn't be read just now: try again in a moment")
            }
        }
    }

    /** Where you look, level, for the place's sounds to come from where their sources are. */
    private fun lookingAt(): Vector3 = scene.getViewerPose().forward()

    /** A film starts: you're seated where you are, the window steps aside. */
    private fun enterTheater() {
        seat = seatHere()
        Theater.poke()
    }

    /** The film ends: the screen goes, the window comes back where it was. */
    private fun leaveTheater() {
        screen.clear()
        // Browsing goes on from the same seat: in the cinema, its hall stays round you.
        browseSeat = seat
        seat = null
        shownPlace = null
    }

    /** Where you sit while browsing away from your room; null in it, so going back out seats you afresh. */
    private var browseSeat: TheaterScreen.Seat? = null

    /**
     * The place's own surroundings round [s] for the screen [spec]: the
     * cinema's hall, the cabin, the lakeside's pontoon; each made again only
     * when the seat or the screen changes. None for a tilted seat (you're
     * lying back, looking up) or a 180° or 360° film.
     */
    private fun surround(place: Stage.Place, s: TheaterScreen.Seat, spec: TheaterGeometry.Spec) {
        if (s.tilted || spec.projection != Projection.FLAT) return
        val eye = s.eye.y
        val middle = eye + spec.aboveEyesM
        val slope = TheaterGeometry.footSlope(spec)
        when (place) {
            Stage.Place.CINEMA -> theatre.build(s.floor, spec.widthM, spec.heightM, middle, spec.distanceM, eye)
            Stage.Place.CABIN -> cabin.build(s.floor, listOf(spec.widthM, spec.heightM, middle, spec.distanceM, eye, slope)) {
                Cabin.build(spec.widthM, spec.heightM, middle, spec.distanceM, eye, slope)
            }
            Stage.Place.LAKE -> dock.build(s.floor, listOf(eye, slope)) { Dock.build(eye, slope) }
            Stage.Place.CLOUDS -> terrace.build(s.floor, listOf(eye, slope)) { Terrace.build(eye, slope) }
            Stage.Place.MOON -> moonBase.build(s.floor, listOf(eye, slope)) { MoonBase.build(eye, slope) }
            Stage.Place.STATION -> station.build(s.floor, listOf(spec.widthM, spec.heightM, middle, spec.distanceM, eye)) {
                Station.build(spec.widthM, spec.heightM, middle, spec.distanceM, eye)
            }
            Stage.Place.ROOM, Stage.Place.VOID, Stage.Place.SPACE -> {}
        }
    }

    /** The big screen while no film plays: the chosen size and curve, a 16:9 picture. */
    private fun browseSpec(place: Stage.Place) = TheaterGeometry.spec(
        Theater.Request(Projection.FLAT, app.lumiere.android.api.StereoLayout.MONO, 1920, 1080),
        place, Stage.screenSize, Stage.curved)

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
            TheaterScreen.current?.let { spec -> surround(Stage.place, s, spec) }
            if (windowMode == WindowMode.ASKED) setWindow(WindowMode.ASKED)
            if (transportShown) placeTransport()
        } else {
            // Away from your room the hall (the cabin, the pontoon) and the big screen come round you where you are now.
            if (Stage.place != Stage.Place.ROOM) browseSeat = seatHere()
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
        window.setComponent(Transform(WindowPlacement.pose(head.t, flat(ahead.forward()), ahead.q, Stage.place != Stage.Place.ROOM)))
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
        // The panel's middle sits above the bar's by half the clear space over it.
        val clearAbove = Window.TRANSPORT_WIDTH_M * (Window.TRANSPORT_HEIGHT_DP - Window.TRANSPORT_BAR_DP) / Window.TRANSPORT_WIDTH_DP
        transport.setComponent(Transform(nearYou(Window.TRANSPORT_DISTANCE_M, Window.TRANSPORT_BELOW_EYES_M - clearAbove / 2)))
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
