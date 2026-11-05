package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.R
import app.lumiere.android.Screen
import app.lumiere.android.player.Theater
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.SpatialFeature
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.ReferenceSpace
import com.meta.spatial.toolkit.ActivityPanelRegistration
import com.meta.spatial.toolkit.AppSystemActivity
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.PanelRegistration
import com.meta.spatial.toolkit.PanelSettings
import com.meta.spatial.toolkit.PanelStyleOptions
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.Scale
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.toolkit.Visible
import com.meta.spatial.toolkit.createPanelEntity
import com.meta.spatial.vr.LocomotionSystem
import com.meta.spatial.vr.VRFeature
import kotlinx.coroutines.launch

/**
 * The theater: what Play in Lumiere's window opens, as Meta's own TV app
 * hands a film to its theater. The film plays on a screen of its own round
 * you, in the place you chose (TheaterStage), with its bar low before you
 * (FilmBar) and its menus just above that (BarMenu). The film's host, the
 * window (TheaterWindow), stays out of sight but for the player's questions.
 * When the film ends, or Back leaves it, the theater closes and the lobby's
 * window is where you left it. The controllers and a thumb's taps are the
 * remote (Remote, Gestures).
 */
class LumiereSpace : AppSystemActivity() {
    private val scope = kotlinx.coroutines.MainScope()
    private var window: Entity? = null
    private var theater: TheaterStage? = null
    private val headset by lazy { getSharedPreferences("lumiere.prefs", MODE_PRIVATE) }
    /** The player has been up: the theater closes once it's gone. */
    private var played = false
    private var opened = 0L

    // ComposeFeature hosts the Compose panels; without it they can't start.
    override fun registerFeatures(): List<SpatialFeature> {
        val features = mutableListOf<SpatialFeature>(VRFeature(this), com.meta.spatial.compose.ComposeFeature())
        // Your room's walls (Space Setup), for the screen on your wall; nothing is read until you ask.
        runCatching { com.meta.spatial.mruk.MRUKFeature(this, systemManager) }
            .onSuccess { mruk = it; features += it }
            .onFailure { android.util.Log.w("Lumiere", "no room understanding: the screen can only be pinned in the air", it) }
        return features
    }

    private var mruk: com.meta.spatial.mruk.MRUKFeature? = null
    private var walls: RoomWalls? = null

    @Deprecated("The headset asks for the spatial data permission the platform way.")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        @Suppress("DEPRECATION") super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RoomWalls.REQUEST)
            walls?.answered(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        OpenApp.pendingPlay = film(intent)
        super.onCreate(savedInstanceState)
        opened = System.currentTimeMillis()
        // Leave, from the film's host, closes the theater; the lobby's window stays.
        OpenApp.quit = { runOnUiThread { finishAndRemoveTask() } }
        Theater.enabled = true
        Theater.ownBar = true
        systemManager.registerSystem(Remote())
    }

    /** Play pressed again in the lobby while the theater is still up: that film now. */
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        film(intent)?.let { p -> OpenApp.state?.let { it.tab(Screen.Home); it.push(p) } ?: run { OpenApp.pendingPlay = p } }
    }

    private fun film(i: android.content.Intent?): Screen.Player? {
        val id = i?.getStringExtra("play") ?: return null
        return Screen.Player(id, i.getDoubleExtra("start", -1.0).takeIf { it >= 0 })
    }

    private fun panel(id: Int, content: @androidx.compose.runtime.Composable () -> Unit, settings: () -> PanelSettings) =
        com.meta.spatial.compose.ComposeViewPanelRegistration(
            id,
            composeViewCreator = { _, context -> androidx.compose.ui.platform.ComposeView(context).apply { setContent { content() } } },
            settingsCreator = { settings() },
        )

    private fun clear(widthM: Float, heightM: Float, widthDp: Float, heightDp: Float) = UIPanelSettings(
        shape = QuadShapeOptions(width = widthM, height = heightM),
        display = DpDisplayOptions(width = widthDp, height = heightDp),
        style = PanelStyleOptions(themeResourceId = R.style.LumiereClearPanel),
    )

    override fun registerPanels(): List<PanelRegistration> = listOf(
        // The film's host: Lumiere's own screens, hidden but for a question the player asks.
        ActivityPanelRegistration(
            R.id.lumiere_window,
            classIdCreator = { TheaterWindow::class.java },
            settingsCreator = {
                UIPanelSettings(
                    shape = QuadShapeOptions(width = Window.WIDTH_M, height = Window.HEIGHT_M),
                    display = DpDisplayOptions(width = Window.WIDTH_DP.toFloat(), height = Window.HEIGHT_DP.toFloat()),
                )
            },
        ),
        // The screen: a video layer the headset draws directly, made for each film at its shape.
        com.meta.spatial.toolkit.VideoSurfacePanelRegistration(
            R.id.lumiere_screen,
            surfaceConsumer = { _, surface -> android.os.Handler(mainLooper).post { Theater.surface = surface } },
            settingsCreator = { _ -> TheaterPanels.screenSettings() },
        ),
        panel(R.id.lumiere_captions, { TheaterCaptions() }) { TheaterPanels.captionSettings() },
        panel(R.id.lumiere_bar, { FilmBar.Panel() }) { TheaterPanels.barSettings() },
        panel(R.id.lumiere_menu, { BarMenu.Panel() }) { clear(BarMenu.WIDTH_M, BarMenu.HEIGHT_M, BarMenu.WIDTH_DP, BarMenu.HEIGHT_DP) },
        panel(R.id.lumiere_places, { PlacePicker.Panel() }) { clear(PlacePicker.WIDTH_M, PlacePicker.WIDTH_M * 2f / 3f, 900f, 600f) },
    )

    override fun onSceneReady() {
        super.onSceneReady()
        // Heights from the floor; holding the Meta button recentres the room on you.
        scene.setReferenceSpace(ReferenceSpace.LOCAL_FLOOR)
        scene.enablePassthrough(true)
        scene.setLightingEnvironment(ambientColor = Vector3(0.6f), sunColor = Vector3(0f), sunDirection = -Vector3(1f, 3f, 2f))
        // Out of sight from the start; where a question would show, before the film is up.
        window = Entity.createPanelEntity(R.id.lumiere_window,
            Transform(Pose(Vector3(0f, Window.HEIGHT_ABOVE_FLOOR_M - TheaterStage.MENU_BELOW_M, TheaterStage.MENU_M))),
            Scale(Vector3(TheaterStage.MENU_SCALE)), Visible(false))
        // The thumbsticks are the remote's arrows here, not a way to walk about the room. The
        // system stays (input reads it every frame; removing it stopped the app at launch), turned off.
        runCatching { systemManager.findSystem<LocomotionSystem>().enableLocomotion(false) }
            .onFailure { android.util.Log.w("Lumiere", "locomotion left on", it) }
        // A thumb's taps and swipes are the remote too; the hands' own turning is off for them.
        runCatching { systemManager.findSystem<com.meta.spatial.vr.HandMicrogestureLocomotionSystem>().enableHandLocomotion(false) }
        runCatching {
            val gestures = systemManager.tryFindSystem<com.meta.spatial.toolkit.MicrogesturesSystem>()
                ?: com.meta.spatial.toolkit.MicrogesturesSystem().also { systemManager.registerSystem(it) }
            // Called from the SDK's own frame loop, where a failure would stop the app: guarded.
            gestures.addListener { gesture, _ ->
                runCatching {
                    // In a film the first tap only brings the bar, as a pinch on it does: no stray pause.
                    val inFilm = OpenApp.state?.top is Screen.Player
                    val wasUp = FilmBar.isUp
                    FilmBar.wake()
                    if (!inFilm || wasUp) Gestures.keysFor(gesture, inFilm).forEach(Remote::deliver)
                }.onFailure { android.util.Log.w("Lumiere", "gesture", it) }
            }
        }.onFailure { android.util.Log.w("Lumiere", "no hand gestures", it) }
        walls = mruk?.let { RoomWalls(this, it) }
        val sky = Sky { e -> systemManager.findSystem<com.meta.spatial.toolkit.SceneObjectSystem>().getSceneObject(e) }
        theater = TheaterStage(scene, ScreenPlace(this), sky, walls) { window }
        FilmLight.enabled = { headset.getBoolean("questFilmLight", true) }
        // Ten times a second: a film starting, its controls coming and going, its end.
        scope.launch {
            while (true) {
                runCatching { theater?.tick() }.onFailure { android.util.Log.w("Lumiere", "theater", it) }
                closeWhenDone()
                kotlinx.coroutines.delay(100)
            }
        }
    }

    /** Back to the lobby once the player has gone, or if it never came (the film couldn't start). */
    private fun closeWhenDone() {
        val playing = OpenApp.state?.top is Screen.Player
        if (playing) played = true
        val gone = played && !playing
        val never = !played && System.currentTimeMillis() - opened > NEVER_STARTED_MS
        if (gone || never) { played = false; opened = Long.MAX_VALUE; finishAndRemoveTask() }
    }

    /** Holding the Meta button: the screen comes back before you (one on your wall stays there). */
    override fun onRecenter(isUserInitiated: Boolean) {
        super.onRecenter(isUserInitiated)
        scope.launch {
            kotlinx.coroutines.delay(250)
            runCatching { theater?.recenter() }.onFailure { android.util.Log.w("Lumiere", "recenter", it) }
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            OpenApp.quit = null
            Theater.enabled = false
            BarMenu.close()
            PlacePicker.open = false
        }
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        super.onDestroy()
    }

    companion object {
        /** How long the film has to start before the theater gives up and returns to the window. */
        const val NEVER_STARTED_MS = 30_000L
    }
}
