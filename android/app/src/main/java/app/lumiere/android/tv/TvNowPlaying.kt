package app.lumiere.android.tv

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.focusable
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.api.LyricLine
import app.lumiere.android.api.currentLyric
import app.lumiere.android.api.lyrics
import app.lumiere.android.music.Music
import app.lumiere.android.music.clock
import app.lumiere.android.ui.LIconButton
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.pillTint
import coil.compose.AsyncImage

/**
 * Music on the projector as Apple Music on Apple TV lays it out, landscape:
 * the cover large and square on the left with the song, the time and the
 * controls under it; on the right the lyrics — the sung line lit and held a
 * third of the way down — or, with none, what plays next. The cover's colours
 * wash the whole screen behind.
 */
@Composable
fun TvNowPlayingScreen(state: AppState) {
    val server = state.server ?: return
    val track = Music.current ?: run {
        Box(Modifier.fillMaxSize().background(Palette.canvas), contentAlignment = Alignment.Center) {
            Text("Nothing playing", style = MaterialTheme.typography.titleLarge)
        }
        return
    }
    var lines by remember { mutableStateOf<List<LyricLine>?>(null) }
    LaunchedEffect(track.id) { lines = null; lines = runCatching { server.lyrics(track.id) }.getOrNull() }
    var showQueue by remember { mutableStateOf(false) }
    val play = remember { FocusRequester() }
    // Down: the lyrics alone, across the whole screen, for singing along; any key brings the rest back.
    var lyricsOnly by remember { mutableStateOf(false) }
    val whole = remember { FocusRequester() }
    LaunchedEffect(lyricsOnly) { if (lyricsOnly) runCatching { whole.requestFocus() } else { kotlinx.coroutines.delay(60); runCatching { play.requestFocus() } } }
    val art = server.imageUrl(track.albumId ?: track.id, "Primary", null, 720)
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(80); runCatching { play.requestFocus() } }

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black)) {
        // The cover, huge and faint, as the wash behind everything.
        AsyncImage(art, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().alpha(0.35f))
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Black.copy(alpha = 0.85f)))))
        val cover = (maxHeight * 0.52f).coerceAtMost(maxWidth * 0.3f)
        val screenH = maxHeight
        Row(Modifier.fillMaxSize().focusRequester(whole).focusable(lyricsOnly).onPreviewKeyEvent { e ->
                if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                when {
                    lyricsOnly -> { lyricsOnly = false; true }
                    e.nativeKeyEvent.keyCode == android.view.KeyEvent.KEYCODE_DPAD_DOWN && !showQueue && !lines.isNullOrEmpty() -> { lyricsOnly = true; true }
                    else -> false
                }
            }.padding(horizontal = 64.dp, vertical = 40.dp), horizontalArrangement = Arrangement.spacedBy(56.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (!lyricsOnly) Column(Modifier.width(cover + 40.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AsyncImage(art, track.album, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(cover).aspectRatio(1f).clip(RoundedCornerShape(10.dp)).background(Palette.surface))
                Spacer(Modifier.height(6.dp))
                Text(track.name, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(track.artists.joinToString(", ").ifEmpty { track.albumArtist }, track.album).joinToString(" — "),
                    fontSize = 16.sp, color = Color.White.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                LinearProgressIndicator(progress = { if (Music.duration > 0) (Music.position / Music.duration).toFloat() else 0f },
                    color = Color.White, trackColor = Color.White.copy(alpha = 0.25f), modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                Row(Modifier.fillMaxWidth()) {
                    Text(clock(Music.position), fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f))
                    Spacer(Modifier.weight(1f))
                    Text("-" + clock((Music.duration - Music.position).coerceAtLeast(0.0)), fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    LIconButton(onClick = { Music.toggleShuffle() }) {
                        Icon(Icons.Default.Shuffle, "Shuffle", tint = pillTint(if (Music.shuffle) Palette.accent else Color.White.copy(alpha = 0.7f)))
                    }
                    LIconButton(onClick = { Music.previous() }) { Icon(Icons.Default.SkipPrevious, "Previous", tint = pillTint(Color.White), modifier = Modifier.size(32.dp)) }
                    LIconButton(onClick = { Music.toggle() }, modifier = Modifier.size(64.dp).focusRequester(play)) {
                        Icon(if (Music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Play or pause",
                            tint = pillTint(Color.White), modifier = Modifier.size(42.dp))
                    }
                    LIconButton(onClick = { Music.next() }) { Icon(Icons.Default.SkipNext, "Next", tint = pillTint(Color.White), modifier = Modifier.size(32.dp)) }
                    // Stop: the music ends and its player is let go.
                    LIconButton(onClick = { Music.stop(); state.pop() }) {
                        Icon(Icons.Default.Stop, "Stop", tint = pillTint(Color.White.copy(alpha = 0.85f)))
                    }
                    LIconButton(onClick = { Music.cycleRepeat() }) {
                        Icon(if (Music.repeat == androidx.media3.common.Player.REPEAT_MODE_ONE) Icons.Default.RepeatOne else Icons.Default.Repeat, "Repeat",
                            tint = pillTint(if (Music.repeat != androidx.media3.common.Player.REPEAT_MODE_OFF) Palette.accent else Color.White.copy(alpha = 0.7f)))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TvPill({ showQueue = false }, selected = !showQueue) { Text("Lyrics") }
                    TvPill({ showQueue = true }, selected = showQueue) { Text("Up Next") }
                }
            }
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
                val l = lines
                if (showQueue || l.isNullOrEmpty()) Queue(state, showQueue || l != null)
                else Lyrics(l, screenH)
            }
        }
    }
}

@Composable
private fun Lyrics(l: List<LyricLine>, height: androidx.compose.ui.unit.Dp) {
    val synced = l.firstOrNull()?.start != null
    val current = if (synced) currentLyric(l, Music.position) else null
    val list = rememberLazyListState()
    // The sung line held about a third of the way down, as Apple Music keeps it.
    LaunchedEffect(current) { current?.let { list.animateScrollToItem(it.coerceAtLeast(0)) } }
    LazyColumn(Modifier.fillMaxHeight(), state = list, userScrollEnabled = false,
        contentPadding = PaddingValues(top = height * 0.3f, bottom = height * 0.6f), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        itemsIndexed(l) { i, line ->
            val lit = !synced || i == current
            val a by animateFloatAsState(if (lit) 1f else if (current != null && i < current) 0.25f else 0.4f, label = "lyric")
            Text(line.text.ifEmpty { "♪" }, fontSize = if (synced) 34.sp else 24.sp, fontWeight = FontWeight.Bold,
                lineHeight = if (synced) 42.sp else 32.sp, color = Color.White, modifier = Modifier.alpha(a).fillMaxWidth())
        }
    }
}

/** What plays next; OK jumps to a song. Said plainly when there are no lyrics. */
@Composable
private fun Queue(state: AppState, asked: Boolean) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (!asked) Text("No lyrics for this song", fontSize = 15.sp, color = Color.White.copy(alpha = 0.55f), modifier = Modifier.padding(bottom = 6.dp))
        Text("Up Next", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val q = Music.queue
            itemsIndexed(q.drop(Music.index + 1).take(30)) { i, t ->
                TvPill({ Music.jump(Music.index + 1 + i) }, Modifier.fillMaxWidth()) {
                    Column {
                        Text(t.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(t.artists.joinToString(", ").ifEmpty { t.albumArtist ?: "" }, style = MaterialTheme.typography.labelMedium, maxLines = 1)
                    }
                }
            }
        }
    }
}
