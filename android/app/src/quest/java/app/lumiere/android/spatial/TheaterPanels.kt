package app.lumiere.android.spatial

import app.lumiere.android.R
import com.meta.spatial.runtime.StereoMode
import com.meta.spatial.toolkit.DpDisplayOptions
import com.meta.spatial.toolkit.MediaPanelRenderOptions
import com.meta.spatial.toolkit.MediaPanelSettings
import com.meta.spatial.toolkit.PanelStyleOptions
import com.meta.spatial.toolkit.PixelDisplayOptions
import com.meta.spatial.toolkit.QuadShapeOptions
import com.meta.spatial.toolkit.UIPanelSettings

/** The Theater's panels as the SDK asks for them while making each: the film's screen and its captions. */
object TheaterPanels {
    fun screenSettings(): MediaPanelSettings {
        val s = TheaterStage.current ?: TheaterGeometry.room(1920, 1080)
        val f = TheaterStage.currentFormat
        val shape = when (f) {
            StereoDetect.Format.VR180_SBS -> com.meta.spatial.toolkit.Equirect180ShapeOptions(TheaterGeometry.SPHERE_RADIUS_M)
            StereoDetect.Format.VR360_MONO, StereoDetect.Format.VR360_OU -> com.meta.spatial.toolkit.Equirect360ShapeOptions(TheaterGeometry.SPHERE_RADIUS_M)
            else -> QuadShapeOptions(width = s.widthM, height = s.heightM)
        }
        // The headset shows each eye its own half: left and right, or top and bottom.
        val eyes = when (f) {
            StereoDetect.Format.SBS, StereoDetect.Format.VR180_SBS -> StereoMode.LeftRight
            StereoDetect.Format.OU, StereoDetect.Format.VR360_OU -> StereoMode.UpDown
            // In 2D: the left (or upper) eye's picture alone, to both eyes.
            StereoDetect.Format.SBS_2D -> StereoMode.MonoLeft
            StereoDetect.Format.OU_2D -> StereoMode.MonoUp
            else -> StereoMode.None
        }
        return MediaPanelSettings(shape, PixelDisplayOptions(s.pixelWidth, s.pixelHeight), MediaPanelRenderOptions(false, eyes))
    }

    fun barSettings(): UIPanelSettings = UIPanelSettings(
        shape = QuadShapeOptions(width = FilmBar.WIDTH_M, height = FilmBar.WIDTH_M / FilmBar.ASPECT),
        display = DpDisplayOptions(width = FilmBar.WIDTH_DP, height = FilmBar.WIDTH_DP / FilmBar.ASPECT),
        style = PanelStyleOptions(themeResourceId = R.style.LumiereClearPanel),
    )

    fun captionSettings(): UIPanelSettings {
        val c = TheaterGeometry.captions(TheaterStage.current ?: TheaterGeometry.room(1920, 1080))
        return UIPanelSettings(
            shape = QuadShapeOptions(width = c.widthM, height = c.heightM),
            display = DpDisplayOptions(width = c.widthDp, height = c.widthDp * c.heightM / c.widthM, dpi = 160),
            style = PanelStyleOptions(themeResourceId = R.style.LumiereClearPanel),
        )
    }
}

/** [v] laid flat: the way you face, ignoring how far you look up or down. */
internal fun level(v: com.meta.spatial.core.Vector3): com.meta.spatial.core.Vector3 {
    val flat = com.meta.spatial.core.Vector3(v.x, 0f, v.z)
    return if (flat.length() < 1e-3f) com.meta.spatial.core.Vector3(0f, 0f, 1f) else flat.normalize()
}
