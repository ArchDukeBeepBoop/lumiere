package app.lumiere.android.local

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.music.PlaybackService
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.iosClick

/**
 * The phone's own songs, playing on after their page is left: one player
 * kept for the app's life, on the lock screen through the music service, and
 * a bar along the bottom while it plays. Music from the Mac and songs from
 * the phone never play over each other.
 */
object LocalAudio {
    var player: ExoPlayer? = null
        private set
    var title by mutableStateOf<String?>(null)
        private set
    var playing by mutableStateOf(false)
        private set
    var uri by mutableStateOf<String?>(null)
        private set
    /** What is playing now and what follows, for the queue on the song's page. */
    var queue by mutableStateOf<List<LocalEntry>>(emptyList())
        private set
    var index by mutableStateOf(0)
        private set
    val current: LocalEntry? get() = queue.getOrNull(index)

    fun play(context: Context, queue: List<LocalEntry>, start: Int) {
        app.lumiere.android.music.Music.player?.pause()
        val p = player ?: ExoPlayer.Builder(context.applicationContext)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            .setHandleAudioBecomingNoisy(true).build().also { built ->
                built.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
                    override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                        title = item?.mediaMetadata?.title?.toString(); uri = item?.mediaId; index = built.currentMediaItemIndex
                    }
                })
                player = built
            }
        p.setMediaItems(queue.map { e ->
            MediaItem.Builder().setMediaId(e.uri).setUri(Uri.parse(e.uri))
                .setMediaMetadata(MediaMetadata.Builder().setTitle(e.name).setArtist(e.artist ?: "On This Phone").setAlbumTitle(e.album).build()).build()
        }, start.coerceIn(0, queue.lastIndex), 0)
        p.prepare(); p.play()
        title = queue.getOrNull(start)?.name; uri = queue.getOrNull(start)?.uri
        this.queue = queue; index = start.coerceIn(0, queue.lastIndex)
        PlaybackService.video = p
        context.startService(Intent(context, PlaybackService::class.java))
    }

    fun toggle() = player?.let { if (it.isPlaying) it.pause() else it.play() }
    fun next() = player?.seekToNextMediaItem()

    /** Off, and the lock screen handed back to the Mac's music. */
    fun stop() {
        val p = player ?: return
        p.stop(); p.clearMediaItems()
        if (PlaybackService.video === p) PlaybackService.video = null
        title = null; uri = null; playing = false; queue = emptyList(); index = 0
    }
}

/** The bar along the bottom while a phone song plays; a tap opens its page, a swipe off either side stops it. */
@Composable
fun LocalMiniBar(state: AppState) {
    val name = LocalAudio.title ?: return
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Row(Modifier.fillMaxWidth().padding(8.dp).clip(RoundedCornerShape(12.dp)).background(Palette.surfaceRaised)
            .pointerInput(Unit) { var dx = 0f; detectHorizontalDragGestures(onDragEnd = { if (kotlin.math.abs(dx) > 200) LocalAudio.stop(); dx = 0f }) { _, d -> dx += d } }
            .iosClick { LocalAudio.uri?.let { state.push(Screen.LocalFile(it, name)) } }.padding(8.dp).height(48.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(6.dp)).background(Palette.surface), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.MusicNote, null, tint = Palette.textSecondary)
            }
            Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                Text(name, style = IosType.headline, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(LocalAudio.current?.artist ?: "On This Phone", style = IosType.footnote, color = Palette.textSecondary, maxLines = 1)
            }
            IconButton(onClick = { LocalAudio.toggle() }) {
                Icon(if (LocalAudio.playing) Icons.Default.Pause else Icons.Default.PlayArrow, "Play or pause", tint = Palette.textPrimary)
            }
            IconButton(onClick = { LocalAudio.next() }) { Icon(Icons.Default.SkipNext, "Next", tint = Palette.textPrimary) }
        }
    }
}
