package app.lumiere.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND

/**
 * Top Shelf's moving picture: after six seconds on the spotlight, a silent
 * stretch from a quarter of the way in fades over the still. Only for a film
 * or episode, only while the spotlight has the remote, and released the moment
 * it leaves — one decoder, never kept.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun BannerPreview(state: AppState, item: Item?, active: Boolean) {
    val server = state.server ?: return
    if (!state.settings.bannerPreviews || item == null || !item.isPlayable || !active) return
    var ready by remember(item.id) { mutableStateOf(false) }
    var start by remember(item.id) { mutableStateOf(false) }
    LaunchedEffect(item.id) { kotlinx.coroutines.delay(6_000); start = true }
    if (!start) return
    val context = LocalContext.current
    val player = remember(item.id) {
        ExoPlayer.Builder(context).build().apply {
            volume = 0f
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(MediaItem.fromUri(server.streamUrl(item.id, item.mediaSourceId)),
                ((item.runtimeTicks ?: 0) / TICKS_PER_SECOND * 1000 / 4))
            addListener(object : Player.Listener {
                override fun onRenderedFirstFrame() { ready = true }
            })
            prepare(); play()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    // Ninety seconds, then the still again.
    LaunchedEffect(player) { kotlinx.coroutines.delay(90_000); ready = false; player.stop() }
    AnimatedVisibility(ready, enter = fadeIn(tween(800)), exit = fadeOut(tween(500))) {
        AndroidView({ PlayerView(it).apply { useController = false; this.player = player
            resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM } }, Modifier.fillMaxSize())
    }
}
