package app.lumiere.android.spatial

import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.StereoMode
import com.meta.spatial.toolkit.CylinderShapeOptions
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.Equirect180ShapeOptions
import com.meta.spatial.toolkit.Equirect360ShapeOptions
import com.meta.spatial.toolkit.Grabbable
import com.meta.spatial.toolkit.GrabbableType
import com.meta.spatial.toolkit.MediaPanelRenderOptions
import com.meta.spatial.toolkit.MediaPanelSettings
import com.meta.spatial.toolkit.PanelStyleOptions
import com.meta.spatial.toolkit.PixelDisplayOptions
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.TransformParent
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.toolkit.createPanelEntity

/**
 * The Theater's screen: a video panel the headset draws directly, made at
 * its real size and shape from a TheaterGeometry.Spec, with its captions'
 * panel over its foot. A new size, curve, place or film makes them again —
 * the one way of sizing a panel proven on the headset — and the player
 * moves its picture across (Theater.surface). Moving you (recentring) only
 * moves them.
 */
class TheaterScreen {
    var entity: Entity? = null
        private set
    private var captions: Entity? = null
    private var made: TheaterGeometry.Spec? = null

    /**
     * Make the screen for [spec] if it differs from the one up; true when it
     * was made anew. [movable]: it has a grab bar and goes wherever you carry
     * it, facing you (your room, the dark); the cinema's belongs to its hall.
     */
    fun follow(spec: TheaterGeometry.Spec, seat: Seat, movable: Boolean): Boolean {
        if (spec == made && movable == madeMovable && entity != null) return false
        clear()
        made = spec
        madeMovable = movable
        current = spec
        val screen = Entity.createPanelEntity(R.id.lumiere_screen, Transform(screenPose(spec, seat)),
            Grabbable(enabled = movable && spec.projection == Projection.FLAT, type = GrabbableType.FACE))
        entity = screen
        // A flat screen's captions ride on it, wherever it's carried; a sphere's stay before you.
        captions = if (spec.projection == Projection.FLAT)
            Entity.createPanelEntity(R.id.lumiere_captions, Transform(captionsOnScreen(spec)), TransformParent(screen))
        else Entity.createPanelEntity(R.id.lumiere_captions, Transform(sphereCaptions(seat)))
        return true
    }

    private var madeMovable = false

    /** Where you now sit: the screen (and a sphere's captions) move with you, unmade. */
    fun place(seat: Seat) {
        val spec = made ?: return
        entity?.setComponent(Transform(screenPose(spec, seat)))
        if (spec.projection != Projection.FLAT) captions?.setComponent(Transform(sphereCaptions(seat)))
    }

    /** The film is over: the screen goes, and the player takes its picture back to the window. */
    fun clear() {
        Theater.surface = null
        entity?.let { runCatching { it.destroy() } }
        captions?.let { runCatching { it.destroy() } }
        entity = null; captions = null; made = null
    }

    private fun screenPose(spec: TheaterGeometry.Spec, seat: Seat): Pose =
        if (spec.projection != Projection.FLAT) Pose(seat.eye, seat.facing)
        else Pose(seat.eye + seat.facing * Vector3(0f, spec.aboveEyesM, spec.distanceM), seat.facing)

    /** Over the screen's foot, just in front of it, in the screen's own frame (you are toward -Z). */
    private fun captionsOnScreen(spec: TheaterGeometry.Spec): Pose {
        val (_, _, up, ahead) = TheaterGeometry.captions(spec)
        return Pose(Vector3(0f, up, -ahead))
    }

    private fun sphereCaptions(seat: Seat): Pose =
        Pose(seat.eye + seat.facing * Vector3(0f, -0.55f, TheaterGeometry.SPHERE_CAPTIONS_DISTANCE_M), seat.facing)

    /**
     * Where you watch from: your eyes, and the way you face — level when you
     * sit or stand, tilted with you when you lie back and look up.
     */
    class Seat(val eye: Vector3, val facing: com.meta.spatial.core.Quaternion, val tilted: Boolean) {
        /** The floor under you, for the cinema's hall (only level seats have one). */
        val floor: Pose get() = Pose(Vector3(eye.x, 0f, eye.z), facing)
    }

    companion object {
        /** The spec being made, for the panels' settings, which the SDK asks for as it makes them. */
        @Volatile var current: TheaterGeometry.Spec? = null

        /** The screen's panel for [spec]: a quad, a curve centred on you, or a half or whole sphere. */
        fun settingsFor(spec: TheaterGeometry.Spec?): MediaPanelSettings {
            val s = spec ?: TheaterGeometry.Spec(Projection.FLAT, StereoLayout.MONO, 3.2f, 1.8f, null, 3f, 0f, 1920, 1080)
            val shape = when {
                s.projection == Projection.HALF_SPHERE -> Equirect180ShapeOptions(TheaterGeometry.SPHERE_RADIUS_M)
                s.projection == Projection.SPHERE -> Equirect360ShapeOptions(TheaterGeometry.SPHERE_RADIUS_M)
                s.radiusM != null -> CylinderShapeOptions(radius = s.radiusM, width = s.widthM, height = s.heightM)
                else -> QuadShapeOptions(width = s.widthM, height = s.heightM)
            }
            return MediaPanelSettings(shape, PixelDisplayOptions(s.pixelWidth, s.pixelHeight),
                MediaPanelRenderOptions(false, stereoModeOf(s.eyes)))
        }

        /** The captions' panel: the screen's scale, laid out 1920 dp across whatever its size. */
        fun captionSettings(spec: TheaterGeometry.Spec?): UIPanelSettings {
            val (w, h) = spec?.let { TheaterGeometry.captions(it).let { c -> c[0] to c[1] } } ?: (2f to 0.5f)
            return UIPanelSettings(
                shape = QuadShapeOptions(width = w, height = h),
                display = DpDisplayOptions(width = CAPTIONS_DP, height = CAPTIONS_DP * h / w, dpi = 160),
                style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
            )
        }

        private const val CAPTIONS_DP = 1920f

        fun stereoModeOf(eyes: StereoLayout): StereoMode = when (eyes) {
            StereoLayout.SIDE_BY_SIDE -> StereoMode.LeftRight
            StereoLayout.TOP_BOTTOM -> StereoMode.UpDown
            StereoLayout.MONO -> StereoMode.None
        }
    }
}
