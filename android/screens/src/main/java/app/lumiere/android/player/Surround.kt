package app.lumiere.android.player

import android.view.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.api.Item
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.projectionIn
import app.lumiere.android.api.surroundEyes

/**
 * 180° and 360° films on a Quest: the picture wraps round you instead of
 * filling a screen. The player asks with [request]; the headset's module
 * puts up a half or whole sphere and hands back its [surface]; the player
 * draws there until the film ends, then takes its picture back.
 */
object Surround {
    /** Set by the Quest's spatial app; elsewhere every film plays on its screen. */
    var enabled = false

    /** What the sphere should be: half or whole, how the eyes are laid out, and the picture's size. */
    class Request(val projection: Projection, val eyes: StereoLayout, val width: Int, val height: Int)

    var request by mutableStateOf<Request?>(null)
    var surface by mutableStateOf<Surface?>(null)

    /** A film is playing round you now. */
    val active: Boolean get() = request != null
}

/**
 * Whether [item] wraps round you, and if it does, the player's picture sent
 * to the sphere once it's up. Explicit tags are seen at once; a bare "360"
 * waits for the picture's size. Returns the projection, for the layout
 * around it: the screen's 3D handling stands aside for a sphere.
 */
@Composable
fun rememberSurround(view: PlayerView, player: ExoPlayer, item: Item?): Projection {
    if (!Surround.enabled || item == null) return Projection.FLAT
    var size by remember(player) { mutableStateOf(player.videoSize) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) { size = videoSize }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    val names = listOfNotNull(item.name, item.path?.substringAfterLast('/'))
    val projection = remember(item.id, size) { projectionIn(names, size.width, size.height) }
    val eyes = remember(item.id, projection, size) { surroundEyes(names, projection, size.width, size.height) }
    // A new sphere only when its kind changes, not each time the size is learnt.
    LaunchedEffect(item.id, projection, eyes) {
        Surround.request = if (projection == Projection.FLAT) null
            else Surround.Request(projection, eyes, size.width, size.height)
    }
    // The sphere's surface, once the headset has made it; the screen's own picture again when it goes.
    val surface = Surround.surface
    DisposableEffect(surface, projection) {
        val wrapped = surface != null && projection != Projection.FLAT
        if (wrapped) player.setVideoSurface(surface)
        onDispose {
            if (wrapped) { player.clearVideoSurface(surface); view.player = null; view.player = player }
        }
    }
    DisposableEffect(Unit) { onDispose { Surround.request = null } }
    return projection
}
