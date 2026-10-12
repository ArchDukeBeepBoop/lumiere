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
    /** Away from your room, the small pane near your hands that chooses what plays (Handset); none on a plain start. */
    private val handset: Entity? = null,
    /** The row of buttons by a raised hand (HandMenu); none on a plain start. */
    private val handMenu: Entity? = null,
    /** The cinema as modelled and baked in Blender (CinemaHall); none on a plain start, or if it never loads. */
    private val cinemaModel: BakedPlace? = null,
) {
    private var seenMountAsks = Stage.mountAsks
    /** The room is read for a mount made before at most once a start, and only if already allowed. */
    private var wallsTried = false
    private val screen = TheaterScreen()
    private val marquee = MarqueeScreen()
    private val sky = Sky()
    private val hold = TheaterHold()
    private val posture = Posture()
    private val handRaise = HandRaise()
    private var handMenuShown = false
    /** Captions before you: the way they face, and since when you've been looking well away from it. */
    private var captionYaw: Vector3? = null
    private var lookedAwaySince = 0L
    /** The film's screen as shown: the player's request, held through the gaps (TheaterHold). */
    private var shownRequest: Theater.Request? = null
    private val theatreMade = lazy { Scenery(Auditorium::colour, Auditorium::surface, { b, _, t -> Auditorium.moves(b, t) }, Auditorium::glows, Auditorium::shape,
        Auditorium::shaded, Auditorium::sided, fivefold = true) }
    private val theatre by theatreMade
    private val cabinMade = lazy { Scenery(Cabin::colour, Cabin::surface, { b, i, t -> Cabin.moves(b.kind, i, t) }, { Cabin.spill(it) == 0f }) }
    private val cabin by cabinMade
    private val dockMade = lazy { Scenery(Dock::colour, Dock::surface, { b, i, t -> Dock.moves(b.kind, i, t) }, { Dock.spill(it) == 0f }) }
    private val dock by dockMade
    private val terraceMade = lazy { Scenery(Terrace::colour, Terrace::surface, { b, i, t -> Terrace.moves(b.kind, i, t) }, { Terrace.spill(it) == 0f }) }
    private val terrace by terraceMade
    private val moonMade = lazy { Scenery(MoonBase::colour, MoonBase::surface, { b, i, t -> MoonBase.moves(b.kind, i, t) }, { MoonBase.spill(it) == 0f }) }
    private val moonBase by moonMade
    private val stationMade = lazy { Scenery(Station::colour, Station::surface, { b, i, t -> Station.moves(b.kind, i, t) }, { Station.spill(it) == 0f }) }
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
    private var handsetShown = false
    /** The place the handset last saw, so arriving somewhere new puts the whole window away again. */
    private var handsetPlace: Stage.Place? = null
    /** Since when a film was asked for from the handset with nothing yet to show for it (0: not waiting). */
    private var stuckSince = 0L
    private var seenAsks = Stage.bringHereAsks
    private var tilted = false
    /** Whether the window was last brought before you for away from your room (low) or for it; null at the start. */
    private var windowAway: Boolean? = null

    // Light: the room's passthrough, or the place round you (the cinema's hall, the cabin, the pontoon).
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    private var displayRate = 0f
    /** The film's light on the left and right walls now, gliding toward the picture's (CinemaLight.easeTint). */
    private var tintLeft: Triple<Float, Float, Float>? = null
    private var tintRight: Triple<Float, Float, Float>? = null
    /** When the last film ended (for the cinema's curtain), and the last frame's time (for its motion). */
    private var endedAt = Long.MIN_VALUE / 2
    private var lastFrame = 0f
    private val usualRate by lazy { runCatching { scene.getConfirmedFrameRate() }.getOrDefault(0f) }

    private enum class WindowMode { HOME, ASKED, HIDDEN }

    private companion object {
        /** Below this, the head isn't tracked yet (or you're lying on the floor): no hall is built round it. */
        const val MIN_EYE_HEIGHT_M = 0.3f
        /** How far you turn from captions before you, and for how long, before they come round to you. */
        const val CAPTION_TURN_DEGREES = 28f
        const val CAPTION_TURN_MS = 700L
        /** How long a film asked for from the handset may take to appear before the window comes to say why. */
        const val STUCK_MS = 6_000L
    }

    /** The film's sound comes from here: the Theater's flat screen, the window, or (in a sphere) all round. */
    /**
     * What moves in the place you're in, [seconds] in: the fire and the
     * candles flicker, the fireflies wander. Every frame (Animator); nothing
     * moves for anyone who asked for less motion.
     */
    fun animate(seconds: Float) {
        val dt = (seconds - lastFrame).coerceIn(0f, 0.1f)
        lastFrame = seconds
        // With less motion asked for, the cinema's curtain stays open and nothing moves.
        if (app.lumiere.android.Motion.reduced) { FrontCurtain.closed = 0f; return }
        FrontCurtain.step(dt)
        cinemaModel?.curtain(FrontCurtain.closed)
        if (theatreMade.isInitialized()) theatre.animate(seconds)
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
        // The baked cinema never came: the modelled hall instead, made now.
        val fellBack = cinemaModel?.failedNow(now) == true
        if (fellBack) shownPlace = null
        if (!on && away) {
            // Not before the headset knows where your head is (at the very start it may read the floor).
            val s = browseSeat ?: seatHere().takeIf { it.eye.y > MIN_EYE_HEIGHT_M }?.also { browseSeat = it }
            if (s != null) {
                val spec = browseSpec(place, s.eye.y)
                surround(place, s, spec)
                marquee.follow(spec, s)
            }
        }
        if (on || !away) marquee.clear()
        if (!away) browseSeat = null
        if (on) {
            val s = seat ?: seatHere().also { seat = it }
            val spec = TheaterGeometry.spec(request!!, place, Stage.screenSize, Stage.curved, Stage.scopeFill, s.eye.y)
            val hung = if (place == Stage.Place.ROOM && request.projection == Projection.FLAT) onYourWall(request, s) else null
            if (hung != null) { if (screen.follow(hung.first, s, movable = false, on = hung.second)) shownPlace = null }
            else if (screen.follow(spec, s, movable = !TheaterGeometry.fixedScreen(place)) || fellBack) {
                surround(place, s, spec)
                shownPlace = null
            }
        }

        // Sat down or stood up a moment ago: the place comes to your new height, still facing the same way.
        val sitting = if (on) seat else browseSeat
        if (sitting != null && !sitting.tilted && Stage.followPosture) {
            val head = scene.getViewerPose()
            if (head.t.y > MIN_EYE_HEIGHT_M && posture.moved(head.t.y, sitting.eye.y, now)) reseat(head.t, sitting)
        }

        // The hand menu: a hand raised and looked at calls it; lowered, it goes.
        val handBusy = watchHand(now)

        // Captions where you want them; before you, they turn when you've looked well away a moment.
        if (on) seat?.let { s -> screen.captionsWanted(s); followCaptions(now) }

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
            val baked = bakedHall()
            baked?.show(hall)
            if (theatreMade.isInitialized() || (hall && baked == null)) theatre.show(hall && baked == null)
            if (cabinMade.isInitialized() || inCabin) cabin.show(inCabin)
            if (dockMade.isInitialized() || onDock) dock.show(onDock)
            if (terraceMade.isInitialized() || onTerrace) terrace.show(onTerrace)
            if (moonMade.isInitialized() || onMoon) moonBase.show(onMoon)
            if (stationMade.isInitialized() || aboard) station.show(aboard)
            sky.show(if (sphere) null else Sky.pictureFor(place))
            shownBrightness = -1f; shownTint = null
        }

        // Away from your room the handset chooses what plays, and the window stays as it is for your room,
        // unless you've asked for it (search, settings, everything else). Somewhere new, the handset again.
        if (place != handsetPlace) { handsetPlace = place; Stage.wholeWindow = false }
        // Whatever only the window can do — signing in, choosing who's watching, a PIN, a report — has it.
        val shown = OpenApp.state
        val needsWindow = shown == null || shown.session == null || shown.choosing || shown.pinFor != null || shown.pinChooseFor != null ||
            shown.crashReport != null
        val compact = away && handset != null && !Stage.wholeWindow && !needsWindow
        // A film asked for from the handset that never comes (an error, a sign-in): the window, to say why.
        if (compact && inPlayer && Theater.controls == null) {
            if (stuckSince == 0L) stuckSince = now else if (now - stuckSince > STUCK_MS) Stage.wholeWindow = true
        } else stuckSince = 0L

        // The window: home while browsing; out of the way in the Theater unless asked for; aside for the wall.
        val wallWanted = PosterWall.open && !on
        val mode = when {
            on && Theater.windowAsked -> WindowMode.ASKED
            on || wallWanted || waiting -> WindowMode.HIDDEN
            compact -> WindowMode.HIDDEN
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

        // The tab bar: there while browsing with the window; the transport has the Theater's controls,
        // and away from your room the handset has its own.
        val showSidebar = !on && !waiting && !compact
        if (showSidebar != sidebarShown) {
            sidebarShown = showSidebar
            if (showSidebar && windowMode == WindowMode.HOME) dockSidebar()
            show(sidebar, showSidebar)
        }
        // The handset: away from your room, while no film plays; before you each time it comes.
        val showHandset = compact && !on && !waiting && !inPlayer
        if (handset != null && showHandset != handsetShown) {
            handsetShown = showHandset
            if (showHandset) placeHandset() else handset.setComponent(Transform(Window.parked()))
            handset.setComponent(Visible(showHandset))
        }

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
        // The cinema's house lights at its own pace; elsewhere a second and a half.
        val slowness = if (!hall) 6f else if (target < brightness) CinemaLight.HALL_DOWN else CinemaLight.HALL_UP
        brightness = if (app.lumiere.android.Motion.reduced) target else CinemaLight.ease(brightness, target, slowness)
        // The colour of the picture now (from its trickplay frames) — its left third on your left, its right on your right —
        // else the title's own; gliding from one to the next.
        fun rgb(c: androidx.compose.ui.graphics.Color?) = c?.let { Triple(it.red, it.green, it.blue) }
        val whole = rgb(Theater.screenColour ?: Ambient.colour)
        val wantLeft = rgb(Theater.screenLeft) ?: whole
        val wantRight = rgb(Theater.screenRight) ?: whole
        tintLeft = if (app.lumiere.android.Motion.reduced) wantLeft else CinemaLight.easeTint(tintLeft, wantLeft)
        tintRight = if (app.lumiere.android.Motion.reduced) wantRight else CinemaLight.easeTint(tintRight, wantRight)
        val left = tintLeft; val right = tintRight
        when {
            hall -> bakedHall()?.light(brightness, left, right) ?: theatre.light(brightness, left, right)
            inCabin -> cabin.light(brightness, left, right)
            onDock -> dock.light(brightness, left, right)
            onTerrace -> terrace.light(brightness, left, right)
            onMoon -> moonBase.light(brightness, left, right)
            aboard -> station.light(brightness, left, right)
            place == Stage.Place.ROOM && !sphere -> lightRoom(brightness, roomTint(left, right))
        }
        // The cinema's front curtain: drawn as a film comes, opening as it starts, drawn a while after it ends.
        FrontCurtain.target = if (place != Stage.Place.CINEMA || app.lumiere.android.Motion.reduced) 0f
            else FrontCurtain.targetFor(waiting, on, now - endedAt)
        if (place != Stage.Place.CINEMA) FrontCurtain.closed = 0f
        return brightness != target || left != wantLeft || right != wantRight || FrontCurtain.closed != FrontCurtain.target || handBusy
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

    /**
     * Captions before you, kept where you look: once you've faced more than
     * [CAPTION_TURN_DEGREES] away from them for a moment, they come round to
     * where you face now — not with every small turn of the head.
     */
    private fun followCaptions(now: Long) {
        if (!screen.captionsNear) { captionYaw = null; return }
        val head = scene.getViewerPose()
        val ahead = flat(head.forward())
        val was = captionYaw ?: ahead.also { captionYaw = it }
        val apart = Math.toDegrees(kotlin.math.acos((was.x * ahead.x + was.z * ahead.z).coerceIn(-1f, 1f).toDouble())).toFloat()
        if (apart < CAPTION_TURN_DEGREES) { lookedAwaySince = 0L; return }
        if (lookedAwaySince == 0L) { lookedAwaySince = now; return }
        if (now - lookedAwaySince < CAPTION_TURN_MS) return
        lookedAwaySince = 0L
        captionYaw = ahead
        screen.turnCaptions(head.t, Quaternion.fromDirection(ahead))
    }

    /**
     * The hand menu: the hand (not a controller) nearest the middle of your
     * view, raised and held, calls it by that hand, facing you; it stays put
     * there while you use it with the other. True while a hand is up or the
     * menu shows, so the looks come quicker.
     */
    private fun watchHand(now: Long): Boolean {
        val menu = handMenu ?: return false
        if (!Stage.handMenu) { if (handMenuShown) showHandMenu(menu, null); return false }
        val head = scene.getViewerPose()
        val gaze = head.forward().normalize()
        val eye = floatArrayOf(head.t.x, head.t.y, head.t.z)
        val look = floatArrayOf(gaze.x, gaze.y, gaze.z)
        val hand = trackedHands().minByOrNull { h ->
            val d = (h - head.t).normalize()
            -(d.x * gaze.x + d.y * gaze.y + d.z * gaze.z)
        }
        val wasShown = handRaise.shown
        val show = handRaise.update(eye, look, hand?.let { floatArrayOf(it.x, it.y, it.z) }, now, app.lumiere.android.ui.HandMenu.touchedAt)
        if (show != handMenuShown) showHandMenu(menu, if (show && !wasShown) hand else null)
        return show || (hand != null && handRaise.raised(eye, look, floatArrayOf(hand.x, hand.y, hand.z)))
    }

    private fun showHandMenu(menu: Entity, by: Vector3?) {
        handMenuShown = by != null
        if (by != null) {
            // Just above the hand (so it doesn't cover the buttons) and a touch toward you, facing your eyes.
            val head = scene.getViewerPose()
            val at = by + Vector3(0f, 0.11f, 0f) + (head.t - by).normalize() * 0.03f
            menu.setComponent(Transform(Pose(at, Quaternion.fromDirection((at - head.t).normalize()))))
        } else menu.setComponent(Transform(Window.parked()))
        menu.setComponent(Visible(by != null))
    }

    /** Where the tracked hands are now — hands, not controllers — from the SDK's body; none if it can't say. */
    private fun trackedHands(): List<Vector3> = runCatching {
        val body = com.meta.spatial.core.Query.where { has(com.meta.spatial.toolkit.AvatarBody.id) }.eval().firstOrNull()
            ?.getComponent<com.meta.spatial.toolkit.AvatarBody>() ?: return emptyList()
        listOf(body.leftHand, body.rightHand).mapNotNull { h ->
            val c = runCatching { h.getComponent<com.meta.spatial.toolkit.Controller>() }.getOrNull() ?: return@mapNotNull null
            if (c.type != com.meta.spatial.toolkit.ControllerType.HAND || !c.isActive) null
            else h.getComponent<Transform>().transform.t
        }
    }.getOrDefault(emptyList())

    /** Seated again at [eye] — sat down or stood up — facing as [was] did: the screen and the place round it follow. */
    private fun reseat(eye: Vector3, was: TheaterScreen.Seat) {
        val s = TheaterScreen.Seat(eye, was.facing, tilted = false)
        if (theaterOn) {
            seat = s
            screen.place(s)
            TheaterScreen.current?.let { spec -> surround(Stage.place, s, spec) }
        } else if (Stage.place != Stage.Place.ROOM) browseSeat = s
        shownPlace = null
    }

    /** A film starts: you're seated where you are, the window steps aside (after it, the handset comes back). */
    private fun enterTheater() {
        seat = seatHere()
        Stage.wholeWindow = false
        Theater.poke()
    }

    /** The film ends: the screen goes, the window comes back where it was. */
    private fun leaveTheater() {
        endedAt = Theater.clockMs()
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
            Stage.Place.CINEMA -> bakedHall()?.place(hallAt(s, Stage.screenSize))
                ?: theatre.build(s.floor, listOf(spec.widthM, spec.heightM, middle, spec.distanceM, eye)) {
                    Auditorium.build(spec.widthM, spec.heightM, middle, spec.distanceM, eye)
                }
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

    /** The big screen while no film plays: the chosen size and curve, a 16:9 picture, for eyes [eyeY] over the floor. */
    private fun browseSpec(place: Stage.Place, eyeY: Float) = TheaterGeometry.spec(
        Theater.Request(Projection.FLAT, app.lumiere.android.api.StereoLayout.MONO, 1920, 1080),
        place, Stage.screenSize, Stage.curved, eyeY = eyeY)

    /** The baked cinema, unless it never loaded. */
    private fun bakedHall(): BakedPlace? = cinemaModel?.takeIf { it.state != BakedPlace.State.FAILED }

    /** Where the cinema's hall goes round [s] seated in [size]'s row: its origin, in the floor's frame under your eyes. */
    private fun hallAt(s: TheaterScreen.Seat, size: Int): Pose {
        val o = CinemaHall.origin(size)
        val floor = s.floor
        return Pose(floor.t + floor.q * Vector3(o[0], o[1], o[2]), floor.q)
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
        if (handsetShown) placeHandset()
    }

    /** The handset near your hands, below the big screen's line of sight, turned up to your eyes. */
    private fun placeHandset() {
        handset?.setComponent(Transform(nearYou(Window.HANDSET_DISTANCE_M, Window.HANDSET_BELOW_EYES_M)))
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

    /** The tab bar docked beside the window's left edge — as wide as the window is now — and from there it's yours to move. */
    private fun dockSidebar() {
        sidebar.setComponent(Transform(Docking.beside(window.getComponent<Transform>().transform, windowWidth())))
    }

    /**
     * The window's width now: its corners resize it, so the default is only
     * where it starts. Read from the SDK's own record of its size, if it has one.
     */
    private fun windowWidth(): Float {
        val measured = runCatching {
            when {
                window.hasComponent<com.meta.spatial.isdk.IsdkPanelDimensions>() ->
                    window.getComponent<com.meta.spatial.isdk.IsdkPanelDimensions>().dimensions.x
                window.hasComponent<com.meta.spatial.toolkit.PanelDimensions>() ->
                    window.getComponent<com.meta.spatial.toolkit.PanelDimensions>().dimensions.x
                else -> null
            }
        }.getOrNull()
        return measured?.takeIf { it in Window.MIN_WIDTH_M * 0.8f..Window.MAX_WIDTH_M * 1.2f } ?: Window.WIDTH_M
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

    /**
     * The film's colour for your room's passthrough: both halves together, in
     * steps of a thirty-second, so the table isn't rebuilt for each small glide.
     */
    private fun roomTint(left: Triple<Float, Float, Float>?, right: Triple<Float, Float, Float>?): Triple<Float, Float, Float>? {
        val l = left ?: right ?: return null
        val r = right ?: l
        fun q(v: Float) = kotlin.math.round(v * 32f) / 32f
        return Triple(q((l.first + r.first) / 2), q((l.second + r.second) / 2), q((l.third + r.third) / 2))
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
