package app.lumiere.android.player

import android.view.SurfaceView
import androidx.annotation.OptIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.eyeAspect

/**
 * True 3D on a Quest, in Lumiere's own player: Horizon OS shows a video
 * surface to the two eyes separately when asked (metavr.view.SurfaceViewExt,
 * as DeadEasy Player found, MIT). The subtitles are drawn above the surface,
 * not in it, so they stay one flat line for both eyes. Elsewhere, and where
 * the system doesn't offer it, the film plays flat.
 */
object Stereo3D {
    private const val MONO = 0
    private const val LEFT_RIGHT = 1
    private const val TOP_BOTTOM = 2

    /** Asks the headset to split [surface] for the eyes; false where it can't. */
    fun compose(surface: SurfaceView, layout: StereoLayout): Boolean = runCatching {
        val ext = Class.forName("metavr.view.SurfaceViewExt")
        val set = ext.getMethod("setStereoComposition", SurfaceView::class.java, Int::class.javaPrimitiveType)
        set.invoke(null, surface, when (layout) {
            StereoLayout.SIDE_BY_SIDE -> LEFT_RIGHT
            StereoLayout.TOP_BOTTOM -> TOP_BOTTOM
            StereoLayout.MONO -> MONO
        })
        surface.post { surface.requestLayout(); surface.invalidate() }
        true
    }.getOrDefault(false)
}

/**
 * Plays [layout] in 3D on a Quest for as long as the player is shown, and
 * frames the picture at one eye's shape. Returns what to tell the viewer
 * once: "3D", "flat" when the headset can't, or null when there's nothing to say.
 */
@OptIn(UnstableApi::class)
@Composable
fun rememberStereo(view: PlayerView, player: ExoPlayer, layout: StereoLayout): String? {
    var said by remember(layout) { mutableStateOf<String?>(null) }
    DisposableEffect(view, player, layout) {
        if (!app.lumiere.android.AppBuild.quest || layout == StereoLayout.MONO) return@DisposableEffect onDispose { }
        val surface = view.videoSurfaceView as? SurfaceView
        val on = surface != null && Stereo3D.compose(surface, layout)
        said = if (on) "3D" else "flat"
        val frame = view.findViewById<AspectRatioFrameLayout>(androidx.media3.ui.R.id.exo_content_frame)
        // PlayerView frames the whole picture; afterwards, one eye's half of it.
        val reshape = object : Player.Listener {
            override fun onVideoSizeChanged(size: VideoSize) {
                if (on && size.width > 0) frame?.post {
                    frame.setAspectRatio(eyeAspect(layout, (size.width * size.pixelWidthHeightRatio).toInt(), size.height))
                }
            }
        }
        player.addListener(reshape)
        reshape.onVideoSizeChanged(player.videoSize)
        onDispose {
            player.removeListener(reshape)
            if (on && surface != null) Stereo3D.compose(surface, StereoLayout.MONO)
        }
    }
    return said
}
