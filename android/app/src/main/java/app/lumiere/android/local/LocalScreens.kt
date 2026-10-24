package app.lumiere.android.local

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.IosButton
import app.lumiere.android.ui.IosLargeTitle
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette

/** The list a song was chosen from, so the next one follows. */
object LocalQueue {
    var items: List<LocalEntry> = emptyList()
}

/**
 * A phone file playing: Media3's own player, its controls for scrubbing and
 * pausing, sideways for a video; Back stops it. Nothing is reported to the
 * Mac — the file is not in the library.
 */
@Composable
fun LocalPlayerScreen(state: AppState, uri: String, name: String) {
    val context = LocalContext.current
    val audio = remember(uri) { context.contentResolver.getType(Uri.parse(uri))?.startsWith("audio") == true }
    app.lumiere.android.player.ImmersiveLandscape(enabled = !audio)
    val queue = remember(uri) { LocalQueue.items.takeIf { q -> q.any { it.uri == uri } } ?: listOf(LocalEntry(uri, name, !audio)) }
    // A song goes to the kept player, so it plays on after this page; a video plays here and stops with it.
    // Started before the page draws, so the page has its player from the first frame.
    if (audio) remember(uri) {
        if (LocalAudio.uri != uri || LocalAudio.player == null) LocalAudio.play(context, queue, queue.indexOfFirst { it.uri == uri }.coerceAtLeast(0))
    }
    val player = remember(uri) {
        if (audio) null else {
            app.lumiere.android.music.Music.player?.pause()
            LocalAudio.player?.pause()
            ExoPlayer.Builder(context).build().apply {
                setMediaItems(queue.map { e -> MediaItem.Builder().setUri(Uri.parse(e.uri))
                    .setMediaMetadata(MediaMetadata.Builder().setTitle(e.name).build()).build() },
                    queue.indexOfFirst { it.uri == uri }.coerceAtLeast(0), 0)
                prepare(); play()
            }
        }
    } ?: LocalAudio.player ?: return
    DisposableEffect(player) { onDispose { if (!audio) player.release() } }
    BackHandler { state.pop() }
    // A song: Apple Music's Now Playing, the kept player behind it.
    if (audio) { LocalNowPlaying(state); return }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val many = LocalQueue.items.size > 1 && LocalQueue.items.any { it.uri == uri }
        AndroidView({ PlayerView(it).apply {
            this.player = player; keepScreenOn = !audio; setShowNextButton(many || audio); setShowPreviousButton(many || audio)
            // A song's controls stay on screen; there is no picture for them to hide from.
            if (audio) { controllerShowTimeoutMs = 0; controllerHideOnTouch = false; showController() }
        } },
            Modifier.fillMaxSize().then(if (audio) Modifier.navigationBarsPadding() else Modifier))
        var title by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(name) }
        DisposableEffect(player) {
            val l = object : androidx.media3.common.Player.Listener {
                override fun onMediaMetadataChanged(m: MediaMetadata) { m.title?.let { title = it.toString() } }
            }
            player.addListener(l); onDispose { player.removeListener(l) }
        }
        if (audio) title = LocalAudio.title ?: title
        if (audio) Text(title, style = IosType.title, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 60.dp, start = 24.dp, end = 24.dp))
    }
}
