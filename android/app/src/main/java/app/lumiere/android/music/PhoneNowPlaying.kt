package app.lumiere.android.music

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.LyricLine
import app.lumiere.android.api.lyrics
import app.lumiere.android.ui.Ambient
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.iosClick
import coil.compose.AsyncImage

/**
 * Now Playing on a phone, as Apple Music's: the page takes the cover's
 * colour; the cover large, sinking back a little while paused; the song and
 * who sings it; a thin bar to scrub, the time left beside it; the three big
 * controls; and along the foot lyrics, shuffle, repeat and the queue — lyrics
 * and the queue each taking the page, the cover small above them. Swipe down
 * to close.
 */
@Composable
fun PhoneNowPlaying(state: AppState) {
    val server = state.server ?: return
    val context = LocalContext.current
    val track = Music.current ?: run { Text("Nothing playing", Modifier.statusBarsPadding().padding(24.dp), color = Palette.textSecondary); return }
    var mode by remember { mutableStateOf(0) } // 0 cover, 1 lyrics, 2 queue
    var lines by remember { mutableStateOf<List<LyricLine>?>(null) }
    LaunchedEffect(track.id) { lines = null; lines = runCatching { server.lyrics(track.id) }.getOrNull() }
    val art = server.imageUrl(track.albumId ?: track.id, "Primary", null, 900)
    var tint by remember(track.albumId) { mutableStateOf<Color?>(null) }
    LaunchedEffect(track.albumId) { tint = runCatching { Ambient.average(context, server.imageUrl(track.albumId ?: track.id, "Primary", null, 120)) }.getOrNull() }
    val ground = tint?.let { lerp(Color.Black, it, 0.62f) } ?: Palette.surfaceRaised
    val cover by animateFloatAsState(if (Music.isPlaying) 1f else 0.8f, spring(dampingRatio = 0.62f, stiffness = 260f), label = "cover")
    var pulled by remember { mutableFloatStateOf(0f) }

    Box(Modifier.fillMaxSize()
        .graphicsLayer { translationY = pulled.coerceAtLeast(0f) }
        .background(Brush.verticalGradient(listOf(ground, lerp(ground, Color.Black, 0.55f), Color.Black)))
        .then(if (mode == 0) Modifier.pointerInput(Unit) {
            detectVerticalDragGestures(onDragEnd = { if (pulled > 260f) state.pop(); pulled = 0f }, onDragCancel = { pulled = 0f }) { _, dy -> pulled += dy }
        } else Modifier)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // The grabber: this page pulls down to close.
            Box(Modifier.padding(top = 8.dp, bottom = 14.dp).width(38.dp).height(5.dp).clip(RoundedCornerShape(50))
                .background(Color.White.copy(alpha = 0.35f)).iosClick { state.pop() })
            if (mode == 0) {
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    AsyncImage(art, track.album, contentScale = ContentScale.Crop,
                        modifier = Modifier.widthIn(max = minOf(maxWidth, maxHeight)).fillMaxWidth().aspectRatio(1f)
                            .graphicsLayer { scaleX = cover; scaleY = cover }
                            .shadow((28 * cover).dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp)).background(Palette.surface))
                }
                Spacer(Modifier.height(22.dp))
                Titles(track.name, track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" })
            } else {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    AsyncImage(art, null, contentScale = ContentScale.Crop,
                        modifier = Modifier.size(62.dp).shadow(8.dp, RoundedCornerShape(6.dp)).clip(RoundedCornerShape(6.dp)))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) { Titles(track.name, track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" }) }
                }
                Box(Modifier.weight(1f).fillMaxWidth().padding(top = 10.dp)) { if (mode == 1) Lyrics(lines) else Queue(state) }
            }
            Spacer(Modifier.height(18.dp))
            Scrubber()
            Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically) {
                Control(Icons.Default.SkipPrevious, "Previous", 46) { Music.previous() }
                Control(if (Music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, if (Music.isPlaying) "Pause" else "Play", 66) { Music.toggle() }
                Control(Icons.Default.SkipNext, "Next", 46) { Music.next() }
            }
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Toggle(Icons.Default.FormatQuote, "Lyrics", mode == 1) { mode = if (mode == 1) 0 else 1 }
                Toggle(Icons.Default.Shuffle, "Shuffle", Music.shuffle) { Music.toggleShuffle() }
                Toggle(if (Music.repeat == androidx.media3.common.Player.REPEAT_MODE_ONE) Icons.Default.RepeatOne else Icons.Default.Repeat,
                    "Repeat", Music.repeat != androidx.media3.common.Player.REPEAT_MODE_OFF) { Music.cycleRepeat() }
                Toggle(Icons.AutoMirrored.Filled.QueueMusic, "Queue", mode == 2) { mode = if (mode == 2) 0 else 2 }
            }
        }
    }
}

@Composable
private fun Titles(name: String, by: String) {
    Column(Modifier.fillMaxWidth()) {
        Text(name, style = IosType.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(by, style = IosType.title.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal),
            color = Color.White.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Apple's thin bar: it thickens under the finger; elapsed on the left, what is left on the right. */
@Composable
private fun Scrubber() {
    var held by remember { mutableStateOf<Float?>(null) }
    val thick by animateFloatAsState(if (held != null) 9f else 5f, label = "thick")
    val total = Music.duration.coerceAtLeast(1.0)
    val at = held?.toDouble()?.times(total) ?: Music.position
    Column(Modifier.fillMaxWidth()) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(24.dp)
            .pointerInput(Unit) {
                detectTapGestures { o -> Music.seek((o.x / size.width).coerceIn(0f, 1f) * Music.duration) }
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { o -> held = (o.x / size.width).coerceIn(0f, 1f) },
                    onDragEnd = { held?.let { Music.seek(it * Music.duration) }; held = null },
                    onDragCancel = { held = null },
                ) { c, _ -> held = (c.position.x / size.width).coerceIn(0f, 1f) }
            }, contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth().height(thick.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.22f))) {
                Box(Modifier.fillMaxWidth((at / total).toFloat().coerceIn(0f, 1f)).height(thick.dp)
                    .background(Color.White.copy(alpha = if (held != null) 1f else 0.7f)))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text(clock(at), style = IosType.caption, color = Color.White.copy(alpha = 0.55f), modifier = Modifier.weight(1f))
            Text("-" + clock((Music.duration - at).coerceAtLeast(0.0)), style = IosType.caption, color = Color.White.copy(alpha = 0.55f))
        }
    }
}

@Composable
private fun Control(icon: ImageVector, label: String, size: Int, onClick: () -> Unit) {
    Box(Modifier.size((size + 16).dp).clip(RoundedCornerShape(50)).iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(size.dp))
    }
}

@Composable
private fun Toggle(icon: ImageVector, label: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(42.dp).clip(RoundedCornerShape(10.dp)).background(if (on) Color.White.copy(alpha = 0.2f) else Color.Transparent)
        .iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = if (on) Color.White else Color.White.copy(alpha = 0.55f), modifier = Modifier.size(24.dp))
    }
}
