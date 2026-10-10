package app.lumiere.android.spatial

import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Surround
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.runtime.Scene
import com.meta.spatial.runtime.StereoMode
import com.meta.spatial.toolkit.Equirect180ShapeOptions
import com.meta.spatial.toolkit.Equirect360ShapeOptions
import com.meta.spatial.toolkit.MediaPanelRenderOptions
import com.meta.spatial.toolkit.MediaPanelSettings
import com.meta.spatial.toolkit.PixelDisplayOptions
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.createPanelEntity

/**
 * The sphere a 180° or 360° film is shown on: made when the player asks
 * (Surround.request), centred on you and turned to where you face, and
 * taken down when the film ends. Nothing exists, and nothing is drawn, the
 * rest of the time.
 */
class SurroundSphere(private val scene: Scene) {
    private var entity: Entity? = null
    private var shownFor: Pair<Projection, StereoLayout>? = null

    /** Follows the player's request; true while a sphere is up. */
    fun follow(): Boolean {
        val r = Surround.request
        val kind = r?.let { it.projection to it.eyes }
        if (kind == shownFor) return entity != null
        entity?.let { runCatching { it.destroy() } }
        entity = null
        Surround.surface = null
        shownFor = kind
        if (r != null) {
            val head = scene.getViewerPose()
            val facing = head.removePitchAndRoll()
            entity = Entity.createPanelEntity(R.id.lumiere_surround, Transform(Pose(head.t, facing.q)))
        }
        return entity != null
    }

    companion object {
        /** A sphere this far out: far enough that its curve and your small movements don't show. */
        const val RADIUS_M = 50f

        /** The panel for [request]: half or whole sphere, the eyes as the film lays them out. */
        fun settingsFor(request: Surround.Request?): MediaPanelSettings {
            val half = request?.projection == Projection.HALF_SPHERE
            val (w, h) = pictureSize(request)
            return MediaPanelSettings(
                if (half) Equirect180ShapeOptions(RADIUS_M) else Equirect360ShapeOptions(RADIUS_M),
                PixelDisplayOptions(w, h),
                MediaPanelRenderOptions(false, stereoModeOf(request?.eyes ?: StereoLayout.MONO)),
            )
        }

        fun stereoModeOf(eyes: StereoLayout): StereoMode = when (eyes) {
            StereoLayout.SIDE_BY_SIDE -> StereoMode.LeftRight
            StereoLayout.TOP_BOTTOM -> StereoMode.UpDown
            StereoLayout.MONO -> StereoMode.None
        }

        /** The film's own size when known, else the usual for its kind; never past what the headset decodes. */
        fun pictureSize(request: Surround.Request?): Pair<Int, Int> {
            if (request != null && request.width > 0 && request.height > 0)
                return request.width.coerceAtMost(MAX_SIDE) to request.height.coerceAtMost(MAX_SIDE)
            val square = request?.eyes == StereoLayout.TOP_BOTTOM && request.projection == Projection.SPHERE
            return if (square) 3840 to 3840 else 3840 to 1920
        }

        private const val MAX_SIDE = 8192
    }
}
