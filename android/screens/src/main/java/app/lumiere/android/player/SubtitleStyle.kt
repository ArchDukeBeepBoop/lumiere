package app.lumiere.android.player

import android.graphics.Color
import android.graphics.Typeface
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import app.lumiere.android.Prefs

/**
 * Plain subtitles (SRT and the like) as films set them: white, with a dark
 * outline or shadow and no box — Android's caption default of white on a
 * black slab was the "black background" on every subtitle. Styled anime
 * subtitles are drawn by libass and keep their own look.
 */
@OptIn(UnstableApi::class)
object SubtitleStyle {
    fun apply(view: PlayerView, prefs: Prefs) {
        val sub = view.subtitleView ?: return
        val edge = when (prefs.subtitleStyle) {
            1 -> CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW
            2 -> CaptionStyleCompat.EDGE_TYPE_NONE
            else -> CaptionStyleCompat.EDGE_TYPE_OUTLINE
        }
        val background = if (prefs.subtitleStyle == 2) Color.argb(170, 0, 0, 0) else Color.TRANSPARENT
        sub.setStyle(CaptionStyleCompat(Color.WHITE, background, Color.TRANSPARENT, edge, Color.BLACK,
            Typeface.create("sans-serif-medium", Typeface.NORMAL)))
        sub.setApplyEmbeddedStyles(true)
        sub.setApplyEmbeddedFontSizes(false)
        sub.setFractionalTextSize(when (prefs.subtitleSize) { 0 -> 0.045f; 2 -> 0.068f; 3 -> 0.08f; else -> 0.056f })
        sub.setBottomPaddingFraction(prefs.subtitleLift)
        view.resizeMode = if (prefs.fillsScreen) androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            else androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
}
