package app.lumiere.android.spatial

import app.lumiere.android.Stage

import androidx.compose.ui.platform.ComposeView
import app.lumiere.android.MainActivity
import app.lumiere.android.ui.SpatialSidebar
import com.meta.spatial.compose.ComposeFeature
import com.meta.spatial.compose.ComposeViewPanelRegistration
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.SpatialFeature
import com.meta.spatial.core.Vector2
import com.meta.spatial.core.Vector3
import com.meta.spatial.isdk.IsdkPanelResize
import com.meta.spatial.isdk.ResizeMode
import com.meta.spatial.runtime.ReferenceSpace
import com.meta.spatial.toolkit.ActivityPanelRegistration
import com.meta.spatial.toolkit.AppSystemActivity
import com.meta.spatial.toolkit.CylinderShapeOptions
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.Grabbable
import com.meta.spatial.toolkit.GrabbableType
import com.meta.spatial.toolkit.PanelRegistration
import com.meta.spatial.toolkit.PanelStyleOptions
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.toolkit.createPanelEntity
import com.meta.spatial.vr.LocomotionSystem
import com.meta.spatial.vr.VRFeature
import kotlinx.coroutines.launch

/**
 * The room: passthrough, and Lumiere's own activity — the same screens as
 * the phone and TV — drawn in one window placed in it. Pinch the window's
 * edge, or grip it with a controller, to carry it somewhere else; it turns
 * to face you as it goes. The sidebar of tabs rides beside its left edge,
 * and for a film the room goes dark around a bigger screen (Cinema).
 */
class LumiereSpace : AppSystemActivity() {
    private val scope = kotlinx.coroutines.MainScope()
    /** A start after two that failed: just the window and its sidebar (StartGuard). */
    private var plain = false

    // ComposeFeature hosts the sidebar's Compose panel; without it the panel can't start.
    override fun registerFeatures(): List<SpatialFeature> {
        val features = mutableListOf<SpatialFeature>(VRFeature(this), ComposeFeature())
        // Your room's walls (Space Setup), for the screen on your wall; left out of a plain start.
        if (!app.lumiere.android.StartGuard.peek(this))
            runCatching { com.meta.spatial.mruk.MRUKFeature(this, systemManager) }.onSuccess { mruk = it; features += it }
                .onFailure { android.util.Log.w("Lumiere", "no room understanding", it) }
        return features
    }

    private var mruk: com.meta.spatial.mruk.MRUKFeature? = null
    private var roomWalls: RoomWalls? = null

    @Deprecated("The headset asks for the spatial data permission the platform way.")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        @Suppress("DEPRECATION") super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RoomWalls.REQUEST)
            roomWalls?.answered(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        plain = app.lumiere.android.StartGuard.begin(this)
        if (plain) android.util.Log.w("Lumiere", "the last starts failed; starting plainly")
        // Up Next, the scrub frames and the song float under the screen, not over it.
        app.lumiere.android.ui.Floating.enabled = !plain
        app.lumiere.android.ui.PosterWall.enabled = !plain
        // A film's sound comes from the screen (ScreenSound tells the player where it is).
        app.lumiere.android.player.ScreenAudio.enabled = !plain
        // Films play in the Theater: their own screen, in your room, the cinema or the dark.
        app.lumiere.android.player.Theater.enabled = !plain
        // Away from your room, the big screen shows the title you're on while you browse.
        app.lumiere.android.ui.Marquee.enabled = !plain
        // And there, a handset near your hands chooses what plays on it (the window stays for your room).
        app.lumiere.android.ui.Handset.enabled = !plain
        app.lumiere.android.Stage.load(this)
        if (!plain) systemManager.registerSystem(Remote())
    }

    override fun registerPanels(): List<PanelRegistration> = listOf(
        ActivityPanelRegistration(
            R.id.lumiere_window,
            classIdCreator = { MainActivity::class.java },
            settingsCreator = {
                // A flat window, as Horizon OS's own are: its corners resize it and the content
                // reflows, at the same text size (IsdkPanelResize, Relayout, set on the entity).
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.WIDTH_M, height = Window.HEIGHT_M),
                    display = DpDisplayOptions(width = Window.WIDTH_DP.toFloat(), height = Window.HEIGHT_DP.toFloat()),
                )
            },
        ),
        ComposeViewPanelRegistration(
            R.id.lumiere_sidebar,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { SpatialSidebar(this@LumiereSpace) } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.SIDEBAR_WIDTH_M, height = Window.SIDEBAR_HEIGHT_M),
                    display = DpDisplayOptions(width = Window.SIDEBAR_WIDTH_DP.toFloat(), height = Window.SIDEBAR_HEIGHT_DP.toFloat()),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
        // The Theater's screen: a video panel at its real size and shape — a quad, a curve, or a
        // half or whole sphere — made for each film and size (TheaterScreen).
        com.meta.spatial.toolkit.VideoSurfacePanelRegistration(
            R.id.lumiere_screen,
            surfaceConsumer = { _, surface ->
                android.os.Handler(mainLooper).post { app.lumiere.android.player.Theater.surface = surface }
            },
            settingsCreator = { _ -> TheaterScreen.settingsFor(TheaterScreen.current) },
        ),
        // Its captions, over the screen's foot at the screen's scale.
        ComposeViewPanelRegistration(
            R.id.lumiere_captions,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.TheaterCaptions() } } },
            settingsCreator = { TheaterScreen.captionSettings(TheaterScreen.current) },
        ),
        // Its transport, near your hands.
        ComposeViewPanelRegistration(
            R.id.lumiere_transport,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.TheaterBar() } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.TRANSPORT_WIDTH_M, height = Window.TRANSPORT_HEIGHT_M),
                    display = DpDisplayOptions(width = Window.TRANSPORT_WIDTH_DP.toFloat(), height = Window.TRANSPORT_HEIGHT_DP.toFloat()),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
        // The handset: away from your room, near your hands, for what plays on the big screen.
        ComposeViewPanelRegistration(
            R.id.lumiere_handset,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.Handset.Panel() } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.HANDSET_WIDTH_M, height = Window.HANDSET_HEIGHT_M),
                    display = DpDisplayOptions(width = Window.HANDSET_WIDTH_DP.toFloat(), height = Window.HANDSET_HEIGHT_DP.toFloat()),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
        // The hand menu: a row of buttons by a raised hand (HandRaise).
        ComposeViewPanelRegistration(
            R.id.lumiere_handmenu,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.HandMenu.Panel() } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.HAND_MENU_WIDTH_M, height = Window.HAND_MENU_HEIGHT_M),
                    display = DpDisplayOptions(width = Window.HAND_MENU_WIDTH_DP.toFloat(), height = Window.HAND_MENU_HEIGHT_DP.toFloat()),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
        // The poster wall: your library curved round you (PosterWall).
        ComposeViewPanelRegistration(
            R.id.lumiere_wall,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.PosterWall.Panel() } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = CylinderShapeOptions(
                        radius = Window.WALL_RADIUS_M,
                        width = Window.WALL_WIDTH_DP / Window.WALL_DP_PER_M,
                        height = Window.WALL_HEIGHT_DP / Window.WALL_DP_PER_M,
                    ),
                    display = DpDisplayOptions(width = Window.WALL_WIDTH_DP.toFloat(), height = Window.WALL_HEIGHT_DP.toFloat(), dpi = Window.WALL_DPI),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
        // The big screen while you browse away from your room: the title you're on (MarqueeScreen).
        ComposeViewPanelRegistration(
            R.id.lumiere_marquee,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.Marquee.Panel() } } },
            settingsCreator = { MarqueeScreen.settingsFor(MarqueeScreen.current) },
        ),
        ComposeViewPanelRegistration(
            R.id.lumiere_ornament,
            composeViewCreator = { _, context -> ComposeView(context).apply { setContent { app.lumiere.android.ui.Floating.Ornament() } } },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.ORNAMENT_WIDTH_M, height = Window.ORNAMENT_HEIGHT_M),
                    display = DpDisplayOptions(width = Window.ORNAMENT_WIDTH_DP.toFloat(), height = Window.ORNAMENT_HEIGHT_DP.toFloat()),
                    style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
                )
            },
        ),
    )

    override fun onSceneReady() {
        super.onSceneReady()
        // The places' modelled parts (Modeller), made as the SDK asks for them.
        runCatching { registerMeshCreator(ModelMeshes.BASE) { entity, uri -> ModelMeshes.create(entity, uri, this) } }
            .onFailure { android.util.Log.e("Lumiere", "no modelled meshes", it) }
        // Heights from the floor, and the long press of the Meta button brings everything back in front.
        scene.setReferenceSpace(ReferenceSpace.LOCAL_FLOOR)
        scene.enablePassthrough(true)
        scene.setLightingEnvironment(
            ambientColor = Vector3(0.6f),
            sunColor = Vector3(0f),
            sunDirection = -Vector3(1f, 3f, 2f),
        )
        // Before you, like any Quest window: a grab bar beneath it to carry it anywhere — it keeps
        // facing you wherever you put it, overhead too — and corners that resize it (ISDK's own).
        val start = Pose(Vector3(0f, Window.HEIGHT_ABOVE_FLOOR_M, Window.DISTANCE_M))
        val window = Entity.createPanelEntity(
            R.id.lumiere_window,
            Transform(start),
            Grabbable(enabled = true, type = GrabbableType.FACE),
            IsdkPanelResize(
                true, ResizeMode.Relayout,
                Vector2(Window.MIN_WIDTH_M, Window.MIN_WIDTH_M * Window.HEIGHT_M / Window.WIDTH_M),
                Vector2(Window.MAX_WIDTH_M, Window.MAX_WIDTH_M * Window.HEIGHT_M / Window.WIDTH_M),
            ),
        )
        // The tab bar: its own panel, with its own grab bar; it starts beside the window's left
        // edge and goes wherever you put it. Recentring docks it again (Cinema.recenter).
        val sidebar = Entity.createPanelEntity(
            R.id.lumiere_sidebar,
            Transform(Docking.beside(start, Window.WIDTH_M)),
            Grabbable(enabled = true, type = GrabbableType.FACE),
        )
        // Running long enough to count as a good start; the next one tries everything again.
        scope.launch {
            kotlinx.coroutines.delay(app.lumiere.android.StartGuard.SETTLE_MS)
            app.lumiere.android.StartGuard.settled(this@LumiereSpace)
        }
        // The thumbsticks are the remote's arrows here, not a way to walk about the room. The
        // system stays (input reads it every frame; removing it stopped the app at launch), turned off.
        runCatching { systemManager.findSystem<LocomotionSystem>().enableLocomotion(false) }
            .onFailure { android.util.Log.w("Lumiere", "locomotion left on", it) }
        if (plain) return
        // Thumb taps and swipes are the remote too; the hands' own turning is off for them.
        runCatching { systemManager.findSystem<com.meta.spatial.vr.HandMicrogestureLocomotionSystem>().enableHandLocomotion(false) }
        runCatching {
            val gestures = systemManager.tryFindSystem<com.meta.spatial.toolkit.MicrogesturesSystem>()
                ?: com.meta.spatial.toolkit.MicrogesturesSystem().also { systemManager.registerSystem(it) }
            // Called from the SDK's own frame loop, where a failure would stop the app: guarded.
            gestures.addListener { gesture, _ ->
                runCatching {
                    val inPlayer = app.lumiere.android.OpenApp.state?.top is app.lumiere.android.Screen.Player
                    Gestures.keysFor(gesture, inPlayer).forEach(Remote::deliver)
                }.onFailure { android.util.Log.w("Lumiere", "gesture", it) }
            }
        }.onFailure { android.util.Log.w("Lumiere", "no hand gestures", it) }
        // Hidden, and out of the pointer's way, until there's something in it; it can be carried, like the window.
        val ornament = Entity.createPanelEntity(
            R.id.lumiere_ornament,
            Transform(Window.parked()),
            Grabbable(enabled = true, type = GrabbableType.FACE),
            com.meta.spatial.toolkit.Visible(false),
        )
        // The poster wall waits out of sight, and out of the pointer's way, until it's asked for.
        val wall = Entity.createPanelEntity(R.id.lumiere_wall, Transform(Window.parked()), com.meta.spatial.toolkit.Visible(false))
        // The Theater's transport waits out of sight until a film plays; it can be carried too.
        val transport = Entity.createPanelEntity(
            R.id.lumiere_transport, Transform(Window.parked()),
            Grabbable(enabled = true, type = GrabbableType.FACE), com.meta.spatial.toolkit.Visible(false),
        )
        // The handset waits out of sight until you're away from your room; it can be carried too.
        val handset = Entity.createPanelEntity(
            R.id.lumiere_handset, Transform(Window.parked()),
            Grabbable(enabled = true, type = GrabbableType.FACE), com.meta.spatial.toolkit.Visible(false),
        )
        val handMenu = Entity.createPanelEntity(R.id.lumiere_handmenu, Transform(Window.parked()), com.meta.spatial.toolkit.Visible(false))
        roomWalls = mruk?.let { RoomWalls(this, it) }
        // The places as modelled and baked in Blender, those that came with the app; the SDK says when each has loaded.
        val sceneObjects: (com.meta.spatial.core.Entity) -> java.util.concurrent.CompletableFuture<com.meta.spatial.runtime.SceneObject>? =
            { e -> systemManager.findSystem<com.meta.spatial.toolkit.SceneObjectSystem>().getSceneObject(e) }
        fun has(path: String) = runCatching { assets.open(path).close() }.isSuccess
        val picture: (String) -> android.graphics.Bitmap? = { p -> runCatching { assets.open(p).use { android.graphics.BitmapFactory.decodeStream(it) } }.getOrNull() }
        fun model(path: String, curtain: String? = null, rise: Float = 0f) = if (has(path)) BakedPlace(path, curtain, rise, sceneObjects, picture) else null
        val baked = listOfNotNull(
            model(CINEMA_MODEL, CINEMA_CURTAIN, CinemaHall.CURTAIN_RISE)?.let { m ->
                BakedScene(Stage.Place.CINEMA, m) { floor, size -> BakedScene.ahead(floor, CinemaHall.origin(size)) }
            },
            model("environments/cabin.glb")?.let { m ->
                model("environments/cabin_sofa.glb")?.let { sofa ->
                    BakedScene(Stage.Place.CABIN, m, sofa) { floor, size -> BakedScene.ahead(floor, CabinRoom.origin(size)) }
                }
            },
            model("environments/lakeside.glb")?.let { BakedScene(Stage.Place.LAKE, it) },
            model("environments/terrace.glb")?.let { BakedScene(Stage.Place.CLOUDS, it) },
            model("environments/moonbase.glb")?.let { BakedScene(Stage.Place.MOON, it) },
            model("environments/palace.glb", "environments/palace_curtain.glb", CinemaHall.CURTAIN_RISE)?.let { m ->
                BakedScene(Stage.Place.PALACE, m) { floor, size -> BakedScene.ahead(floor, CinemaHall.origin(size)) }
            },
            model("environments/winter.glb")?.let { m ->
                model("environments/cabin_sofa.glb")?.let { sofa ->
                    BakedScene(Stage.Place.WINTER, m, sofa) { floor, size -> BakedScene.ahead(floor, CabinRoom.origin(size)) }
                }
            },
            model("environments/drivein.glb")?.let { BakedScene(Stage.Place.DRIVE_IN, it) },
            model("environments/rooftop.glb")?.let { BakedScene(Stage.Place.ROOFTOP, it) },
            model("environments/sea.glb")?.let { BakedScene(Stage.Place.SEA, it) },
            model("environments/station.glb")?.let { m ->
                BakedScene(Stage.Place.STATION, m) { floor, size -> BakedScene.ahead(floor, StationRoom.origin(size)) }
            },
        )
        runCatching { Director(scene, window, sidebar, ornament, wall, transport, ambience, roomWalls, handset, handMenu, baked).also { director = it }.start(scope) }
            .onFailure { android.util.Log.e("Lumiere", "director unavailable", it) }
        // The place's own sounds, while the app is in front (onResume and onPause start and stop them).
        ambience.start()
        // Flames and fireflies, every frame.
        runCatching { systemManager.registerSystem(Animator { director }) }
            .onFailure { android.util.Log.w("Lumiere", "animation unavailable", it) }
        // The film's sound from where its picture is, every frame.
        runCatching { systemManager.registerSystem(ScreenSound(scene) { director?.soundSource() }) }
            .onFailure { android.util.Log.w("Lumiere", "screen sound unavailable", it) }
    }

    private var director: Director? = null
    /** The place's own sounds: playing only while the app is in front. */
    private val ambience = Ambience()

    override fun onResume() {
        super.onResume()
        if (director != null) ambience.start()
    }

    override fun onPause() {
        ambience.stop()
        super.onPause()
    }

    /**
     * Holding the Meta button: the headset recentres its room space on you,
     * and everything Lumiere shows comes back in front of you, as in any
     * Quest app. A moment's wait first, for the new space to settle.
     */
    override fun onRecenter(isUserInitiated: Boolean) {
        super.onRecenter(isUserInitiated)
        scope.launch {
            kotlinx.coroutines.delay(250)
            runCatching { director?.recenter() }.onFailure { android.util.Log.w("Lumiere", "recenter", it) }
        }
    }

    private companion object {
        /** The cinema's hall and its front curtain, as Scripts/env/cinema.py bakes them. */
        const val CINEMA_MODEL = "environments/cinema.glb"
        const val CINEMA_CURTAIN = "environments/cinema_curtain.glb"
    }

    override fun onDestroy() {
        // Closed, not crashed: not a failed start.
        if (isFinishing) app.lumiere.android.StartGuard.settled(this)
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        super.onDestroy()
    }
}
