package app.lumiere.android.spatial

import androidx.compose.ui.platform.ComposeView
import app.lumiere.android.MainActivity
import app.lumiere.android.ui.SpatialSidebar
import com.meta.spatial.compose.ComposeFeature
import com.meta.spatial.compose.ComposeViewPanelRegistration
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.SpatialFeature
import com.meta.spatial.core.Vector3
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
import com.meta.spatial.toolkit.TransformParent
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
    override fun registerFeatures(): List<SpatialFeature> = listOf(VRFeature(this), ComposeFeature())

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        plain = app.lumiere.android.StartGuard.begin(this)
        if (plain) android.util.Log.w("Lumiere", "the last starts failed; starting plainly")
        app.lumiere.android.Stage.load(this)
        if (!plain) systemManager.registerSystem(Remote())
    }

    override fun registerPanels(): List<PanelRegistration> = listOf(
        ActivityPanelRegistration(
            R.id.lumiere_window,
            classIdCreator = { MainActivity::class.java },
            settingsCreator = {
                UIPanelSettings(
                    shape = CylinderShapeOptions(radius = Window.DISTANCE_M, width = Window.WIDTH_M, height = Window.HEIGHT_M),
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
    )

    override fun onSceneReady() {
        super.onSceneReady()
        // Heights from the floor, and the long press of the Meta button brings everything back in front.
        scene.setReferenceSpace(ReferenceSpace.LOCAL_FLOOR)
        scene.enablePassthrough(true)
        scene.setLightingEnvironment(
            ambientColor = Vector3(0.6f),
            sunColor = Vector3(0f),
            sunDirection = -Vector3(1f, 3f, 2f),
        )
        val window = Entity.createPanelEntity(
            R.id.lumiere_window,
            Transform(Pose(Vector3(0f, Window.HEIGHT_ABOVE_FLOOR_M, Window.DISTANCE_M))),
            Grabbable(enabled = true, type = GrabbableType.PIVOT_Y, minHeight = Window.MIN_HEIGHT_M, maxHeight = Window.MAX_HEIGHT_M),
        )
        // Beside the window's left edge, which the curve brings nearer you, and carried with it.
        val sidebar = Entity.createPanelEntity(
            R.id.lumiere_sidebar,
            Transform(Pose(Vector3(Window.SIDEBAR_X_M, 0f, -Window.EDGE_NEARER_M))),
            TransformParent(window),
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
                    Gestures.keysFor(gesture, inPlayer).forEach { key -> app.lumiere.android.OpenApp.press?.invoke(key) }
                }.onFailure { android.util.Log.w("Lumiere", "gesture", it) }
            }
        }.onFailure { android.util.Log.w("Lumiere", "no hand gestures", it) }
        // The lights go down for a film.
        runCatching { Cinema(scene, window, sidebar).start(scope) }
            .onFailure { android.util.Log.e("Lumiere", "cinema unavailable", it) }
    }

    override fun onDestroy() {
        // Closed, not crashed: not a failed start.
        if (isFinishing) app.lumiere.android.StartGuard.settled(this)
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
        super.onDestroy()
    }
}
