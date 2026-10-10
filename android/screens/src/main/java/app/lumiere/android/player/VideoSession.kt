package app.lumiere.android.player

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import app.lumiere.android.music.PlaybackService

/**
 * On a phone, with Settings' "Keep a video's sound playing" on: the video
 * gets the lock screen's controls, and its sound goes on with the screen off
 * or the app left. Off, leaving the app pauses it — unless it went into its
 * small window. Nothing from the private room ever reaches the lock screen:
 * its titles pause instead.
 */
@Composable
internal fun VideoSession(player: Player, item: Item?, state: AppState) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val private = item != null && (state.roomOpen || item.libraryId in state.privateLibraries)
    val background = state.settings.videoInBackground && item != null && !private
    DisposableEffect(player, item?.id, background) {
        if (background) {
            PlaybackService.video = titled(player, item!!)
            context.startService(Intent(context, PlaybackService::class.java))
        }
        val stops = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && !background && !PictureInPicture.inPip) player.pause()
        }
        lifecycle.addObserver(stops)
        onDispose {
            lifecycle.removeObserver(stops)
            if (background) PlaybackService.video = null
        }
    }
}

/** The player as the lock screen sees it: the title's name and its show's. */
private fun titled(player: Player, item: Item): Player = object : ForwardingPlayer(player) {
    override fun getMediaMetadata(): MediaMetadata = MediaMetadata.Builder()
        .setTitle(item.name)
        .setArtist(if (item.isEpisode) listOfNotNull(item.seriesName, item.episodeLabel).joinToString(" · ") else item.year?.toString())
        .build()
}
