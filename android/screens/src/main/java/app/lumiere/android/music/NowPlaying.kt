package app.lumiere.android.music

import kotlinx.coroutines.launch
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.graphicsLayer
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.LyricLine
import app.lumiere.android.api.currentLyric
import app.lumiere.android.api.lyrics
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import coil.compose.AsyncImage

/** The cover large, the controls, and the lyrics or queue — the Mac's full-screen player. */
@Composable
fun NowPlayingScreen(state: AppState) {
    val server = state.server ?: return
    val track = Music.current ?: run { Text("Nothing playing", Modifier.padding(24.dp)); return }
    val form = LocalFormFactor.current
    var showQueue by remember { mutableStateOf(false) }
    var lines by remember { mutableStateOf<List<LyricLine>?>(null) }
    LaunchedEffect(track.id) { lines = null; lines = server.lyrics(track.id) }
    val art = server.imageUrl(track.albumId ?: track.id, "Primary", null, 800)

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        AsyncImage(art, null, contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize().blur(60.dp).alpha(0.28f))
        Column(Modifier.fillMaxSize().padding(horizontal = form.gutter.dp, vertical = 16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(art, null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(if (form.isTv) 260.dp else 120.dp).clip(RoundedCornerShape(8.dp)))
                Column(Modifier.padding(start = 16.dp).weight(1f)) {
                    Text(track.name, style = MaterialTheme.typography.headlineLarge, maxLines = 2,
                        overflow = TextOverflow.Ellipsis)
                    Text(track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" },
                        style = MaterialTheme.typography.titleMedium, color = Palette.accent)
                    track.album?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
                }
            }
            Slider(
                value = Music.position.toFloat(),
                onValueChange = { Music.seek(it.toDouble()) },
                valueRange = 0f..Music.duration.toFloat().coerceAtLeast(1f),
                modifier = Modifier.padding(top = 12.dp),
            )
            Row(Modifier.fillMaxWidth()) {
                Text(clock(Music.position), style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f))
                Text(clock(Music.duration), style = MaterialTheme.typography.labelMedium)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically) {
                LIconButton(onClick = { Music.toggleShuffle() }) {
                    Icon(Icons.Default.Shuffle, "Shuffle", tint = app.lumiere.android.ui.pillTint(if (Music.shuffle) Palette.accent else Palette.textSecondary))
                }
                LIconButton(onClick = { Music.previous() }) { Icon(Icons.Default.SkipPrevious, "Previous", tint = app.lumiere.android.ui.pillTint(Palette.textPrimary)) }
                LIconButton(onClick = { Music.toggle() }, modifier = Modifier.size(64.dp)) {
                    Icon(if (Music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        if (Music.isPlaying) "Pause" else "Play", tint = Palette.textPrimary, modifier = Modifier.size(44.dp))
                }
                LIconButton(onClick = { Music.next() }) { Icon(Icons.Default.SkipNext, "Next", tint = app.lumiere.android.ui.pillTint(Palette.textPrimary)) }
                LIconButton(onClick = { Music.cycleRepeat() }) {
                    Icon(if (Music.repeat == androidx.media3.common.Player.REPEAT_MODE_ONE) Icons.Default.RepeatOne else Icons.Default.Repeat,
                        "Repeat", tint = if (Music.repeat != androidx.media3.common.Player.REPEAT_MODE_OFF) Palette.accent else Palette.textSecondary)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LChip(!showQueue, { showQueue = false }, { Text("Lyrics") })
                LChip(showQueue, { showQueue = true }, { Text("Queue") })
            }
            Box(Modifier.weight(1f).fillMaxWidth().padding(top = 8.dp)) {
                if (showQueue) Queue(state) else Lyrics(lines)
            }
        }
    }
}

/** Synced lyrics follow the song: the line being sung lit and kept in view; a tap goes to it. */
@Composable
private fun Lyrics(lines: List<LyricLine>?) {
    if (lines == null) {
        Text("No lyrics for this track. A .lrc file named like the track, beside it on the server, is read and synced.",
            style = MaterialTheme.typography.bodyMedium)
        return
    }
    val synced = lines.firstOrNull()?.start != null
    val current = if (synced) currentLyric(lines, Music.position) else null
    val list = rememberLazyListState()
    LaunchedEffect(current) { current?.let { list.animateScrollToItem((it - 2).coerceAtLeast(0)) } }
    LazyColumn(state = list, contentPadding = PaddingValues(vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(if (synced) 14.dp else 4.dp)) {
        itemsIndexed(lines) { i, line ->
            val lit = i == current
            val alpha by animateFloatAsState(if (!synced || lit) 1f else 0.45f, label = "lyric")
            Text(
                line.text.ifEmpty { "♪" },
                fontSize = if (synced) 22.sp else 15.sp,
                fontWeight = if (synced) FontWeight.Bold else FontWeight.Normal,
                color = if (lit) Palette.textPrimary else Palette.textSecondary,
                modifier = Modifier.alpha(alpha).fillMaxWidth()
                    .clickable(enabled = line.start != null) { line.start?.let(Music::seek) },
            )
        }
    }
}

@Composable
private fun Queue(state: AppState) {
    val server = state.server ?: return
    LazyColumn {
        itemsIndexed(Music.queue, key = { i, t -> "$i-${t.id}" }) { i, t ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { TrackRow(t, server, showArt = true) { Music.jump(i) } }
                if (i != Music.index) {
                    LIconButton(onClick = { Music.move(i, i - 1) }, enabled = i > 0) {
                        Icon(Icons.Default.KeyboardArrowUp, "Move up", tint = app.lumiere.android.ui.pillTint(Palette.textSecondary))
                    }
                    LIconButton(onClick = { Music.move(i, i + 1) }, enabled = i < Music.queue.lastIndex) {
                        Icon(Icons.Default.KeyboardArrowDown, "Move down", tint = app.lumiere.android.ui.pillTint(Palette.textSecondary))
                    }
                    LIconButton(onClick = { Music.remove(i) }) { Icon(Icons.Default.Close, "Remove", tint = app.lumiere.android.ui.pillTint(Palette.textSecondary)) }
                }
            }
        }
    }
}

/**
 * The bar along the bottom while music plays; tapping it opens the full
 * player, and swiping it off either side stops the music.
 */
@Composable
fun MiniPlayer(state: AppState) {
    val server = state.server ?: return
    val track = Music.current ?: return
    val slide = remember(track.id) { androidx.compose.animation.core.Animatable(0f) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Row(
            Modifier.fillMaxWidth().padding(8.dp)
                .graphicsLayer { translationX = slide.value; alpha = 1f - kotlin.math.abs(slide.value) / size.width.coerceAtLeast(1f) }
                .pointerInput(track.id) {
                    detectHorizontalDragGestures(
                        onDragEnd = {
                            scope.launch {
                                if (kotlin.math.abs(slide.value) > size.width * 0.35f) {
                                    slide.animateTo(if (slide.value > 0) size.width.toFloat() else -size.width.toFloat())
                                    Music.stop()
                                } else slide.animateTo(0f)
                            }
                        },
                        onDragCancel = { scope.launch { slide.animateTo(0f) } },
                    ) { change, dx -> change.consume(); scope.launch { slide.snapTo(slide.value + dx) } }
                }.clip(RoundedCornerShape(12.dp)).background(Palette.surfaceRaised)
                .focusCard { state.push(Screen.NowPlaying) }.padding(8.dp).height(48.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AsyncImage(server.imageUrl(track.albumId ?: track.id, "Primary", null, 120), null,
                contentScale = ContentScale.Crop, modifier = Modifier.aspectRatio(1f).clip(RoundedCornerShape(6.dp)))
            Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" },
                    style = MaterialTheme.typography.labelMedium, maxLines = 1)
            }
            LIconButton(onClick = { Music.toggle() }) {
                Icon(if (Music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Play or pause",
                    tint = app.lumiere.android.ui.pillTint(Palette.textPrimary))
            }
            LIconButton(onClick = { Music.next() }) { Icon(Icons.Default.SkipNext, "Next", tint = app.lumiere.android.ui.pillTint(Palette.textPrimary)) }
        }
    }
}
