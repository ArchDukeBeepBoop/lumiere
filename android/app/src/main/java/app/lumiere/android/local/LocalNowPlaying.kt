package app.lumiere.android.local

import android.graphics.Bitmap
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.MusicNote
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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import app.lumiere.android.AppState
import app.lumiere.android.music.clock
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.iosClick
import kotlinx.coroutines.delay

/**
 * A phone song playing, as Apple Music's Now Playing: the page in the cover's
 * colour, the cover sinking back while paused, the song and artist, a thin bar
 * to scrub with the time left, the big controls, and shuffle, repeat and the
 * queue along the foot. Swipe down to close; the song plays on.
 */
@Composable
fun LocalNowPlaying(state: AppState) {
    val context = LocalContext.current
    val p = LocalAudio.player ?: return
    val now = LocalAudio.current
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    var shuffle by remember { mutableStateOf(p.shuffleModeEnabled) }
    var repeat by remember { mutableStateOf(p.repeatMode) }
    var showQueue by remember { mutableStateOf(false) }
    LaunchedEffect(p) { while (true) { position = p.currentPosition; duration = p.duration.coerceAtLeast(0); delay(250) } }
    val cover by produceState<Bitmap?>(null, LocalAudio.uri) { value = LocalAudio.uri?.let { MediaLibrary.thumbnail(context, it, 900) } }
    val tint = remember(cover) { cover?.let { b ->
        val s = Bitmap.createScaledBitmap(b, 1, 1, true); Color(s.getPixel(0, 0)) } }
    val ground = tint?.let { lerp(Color.Black, it, 0.6f) } ?: Color(0xFF2C2C2E)
    val sink by animateFloatAsState(if (LocalAudio.playing) 1f else 0.82f, spring(dampingRatio = 0.62f, stiffness = 260f), label = "sink")
    var pulled by remember { mutableFloatStateOf(0f) }

    Box(Modifier.fillMaxSize().graphicsLayer { translationY = pulled.coerceAtLeast(0f) }
        .background(Brush.verticalGradient(listOf(ground, lerp(ground, Color.Black, 0.55f), Color.Black)))
        .pointerInput(Unit) { detectVerticalDragGestures(onDragEnd = { if (pulled > 260f) state.pop(); pulled = 0f }) { _, d -> pulled += d } }) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.padding(top = 8.dp, bottom = 14.dp).width(38.dp).height(5.dp).clip(RoundedCornerShape(50))
                .background(Color.White.copy(alpha = 0.35f)).iosClick { state.pop() })
            if (!showQueue) {
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Box(Modifier.widthIn(max = minOf(maxWidth, maxHeight)).fillMaxWidth().aspectRatio(1f)
                        .graphicsLayer { scaleX = sink; scaleY = sink }.shadow((26 * sink).dp, RoundedCornerShape(12.dp))
                        .clip(RoundedCornerShape(12.dp)).background(Color(0xFF3A3A3C)), contentAlignment = Alignment.Center) {
                        cover?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) }
                            ?: Icon(Icons.Default.MusicNote, null, tint = Color.White.copy(alpha = 0.4f), modifier = Modifier.size(96.dp))
                    }
                }
            } else {
                LazyColumn(Modifier.weight(1f).fillMaxWidth()) {
                    itemsIndexed(LocalAudio.queue) { i, e ->
                        Row(Modifier.fillMaxWidth().clickable { p.seekTo(i, 0); p.play() }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(e.name, style = IosType.body, color = if (i == LocalAudio.index) Color.White else Color.White.copy(alpha = if (i < LocalAudio.index) 0.4f else 0.75f),
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                e.artist?.let { Text(it, style = IosType.footnote, color = Color.White.copy(alpha = 0.5f), maxLines = 1) }
                            }
                            if (i == LocalAudio.index) Icon(Icons.Default.MusicNote, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
            Column(Modifier.fillMaxWidth()) {
                Text(now?.name ?: LocalAudio.title ?: "", style = IosType.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(now?.artist, now?.album).joinToString(" — ").ifEmpty { "On This Phone" },
                    style = IosType.title.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Normal), color = Color.White.copy(alpha = 0.6f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(16.dp))
            Scrub(position, duration) { p.seekTo(it) }
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                Big(Icons.Default.SkipPrevious, "Previous", 46) { if (p.currentPosition > 3000) p.seekTo(0) else p.seekToPreviousMediaItem() }
                Big(if (LocalAudio.playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (LocalAudio.playing) "Pause" else "Play", 66) { LocalAudio.toggle() }
                Big(Icons.Default.SkipNext, "Next", 46) { p.seekToNextMediaItem() }
            }
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Small(Icons.Default.Shuffle, "Shuffle", shuffle) { shuffle = !shuffle; p.shuffleModeEnabled = shuffle }
                Small(if (repeat == Player.REPEAT_MODE_ONE) Icons.Default.RepeatOne else Icons.Default.Repeat, "Repeat", repeat != Player.REPEAT_MODE_OFF) {
                    repeat = when (repeat) { Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL; Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE; else -> Player.REPEAT_MODE_OFF }
                    p.repeatMode = repeat
                }
                Small(Icons.AutoMirrored.Filled.QueueMusic, "Queue", showQueue) { showQueue = !showQueue }
            }
        }
    }
}

@Composable
private fun Scrub(position: Long, duration: Long, onSeek: (Long) -> Unit) {
    var held by remember { mutableStateOf<Float?>(null) }
    val thick by animateFloatAsState(if (held != null) 9f else 5f, label = "thick")
    val total = duration.coerceAtLeast(1)
    val at = held?.let { (it * total).toLong() } ?: position
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(24.dp)
            .pointerInput(total) { detectTapGestures { o -> onSeek(((o.x / size.width).coerceIn(0f, 1f) * total).toLong()) } }
            .pointerInput(total) {
                detectHorizontalDragGestures(onDragStart = { o -> held = (o.x / size.width).coerceIn(0f, 1f) },
                    onDragEnd = { held?.let { onSeek((it * total).toLong()) }; held = null }, onDragCancel = { held = null }) { c, _ ->
                    held = (c.position.x / size.width).coerceIn(0f, 1f)
                }
            }, contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth().height(thick.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.22f))) {
                Box(Modifier.fillMaxWidth((at.toFloat() / total).coerceIn(0f, 1f)).height(thick.dp).background(Color.White.copy(alpha = if (held != null) 1f else 0.7f)))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            Text(clock(at / 1000.0), style = IosType.caption, color = Color.White.copy(alpha = 0.55f), modifier = Modifier.weight(1f))
            Text("-" + clock(((total - at) / 1000.0).coerceAtLeast(0.0)), style = IosType.caption, color = Color.White.copy(alpha = 0.55f))
        }
    }
}

@Composable
private fun Big(icon: ImageVector, label: String, size: Int, onClick: () -> Unit) {
    Box(Modifier.size((size + 16).dp).clip(RoundedCornerShape(50)).iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(size.dp))
    }
}

@Composable
private fun Small(icon: ImageVector, label: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(42.dp).clip(RoundedCornerShape(10.dp)).background(if (on) Color.White.copy(alpha = 0.2f) else Color.Transparent)
        .iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = if (on) Color.White else Color.White.copy(alpha = 0.55f), modifier = Modifier.size(24.dp))
    }
}
