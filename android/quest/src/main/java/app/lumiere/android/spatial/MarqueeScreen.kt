package app.lumiere.android.spatial

import com.meta.spatial.core.Entity
import com.meta.spatial.core.Pose
import com.meta.spatial.core.Vector3
import com.meta.spatial.toolkit.CylinderShapeOptions
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.PanelStyleOptions
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.Transform
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.toolkit.createPanelEntity

/**
 * The big screen while you browse in the cinema, the dark or space: where
 * the film will play, the same size and curve, showing the title you're on
 * (ui.Marquee). Made again, as the Theater's screen is, when its size or
 * curve changes; moved, not made, when you're seated again.
 */
class MarqueeScreen {
    private var entity: Entity? = null
    private var made: TheaterGeometry.Spec? = null
    private var seat: TheaterScreen.Seat? = null

    fun follow(spec: TheaterGeometry.Spec, at: TheaterScreen.Seat) {
        if (spec != made || entity == null) {
            clear()
            made = spec
            current = spec
            seat = at
            entity = Entity.createPanelEntity(R.id.lumiere_marquee, Transform(pose(spec, at)))
        } else if (at !== seat) {
            seat = at
            entity?.setComponent(Transform(pose(spec, at)))
        }
    }

    fun clear() {
        entity?.let { runCatching { it.destroy() } }
        entity = null; made = null; seat = null
    }

    private fun pose(spec: TheaterGeometry.Spec, s: TheaterScreen.Seat) =
        Pose(s.eye + s.facing * Vector3(0f, spec.aboveEyesM, spec.distanceM), s.facing)

    companion object {
        /** The spec being made, for the panel's settings, which the SDK asks for as it makes it. */
        @Volatile var current: TheaterGeometry.Spec? = null

        /** Laid out 1920 dp across whatever its size, so the picture keeps its shape. */
        fun settingsFor(spec: TheaterGeometry.Spec?): UIPanelSettings {
            val w = spec?.widthM ?: 16f
            val h = spec?.heightM ?: 9f
            val shape = spec?.radiusM?.let { CylinderShapeOptions(radius = it, width = w, height = h) }
                ?: QuadShapeOptions(width = w, height = h)
            return UIPanelSettings(
                shape = shape,
                display = DpDisplayOptions(width = MARQUEE_DP, height = MARQUEE_DP * h / w, dpi = 160),
                style = PanelStyleOptions(themeResourceId = R.style.LumiereGlassPanel),
            )
        }

        private const val MARQUEE_DP = 1920f
    }
}
