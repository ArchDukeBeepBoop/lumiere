package app.lumiere.android.player

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.Trickplay
import app.lumiere.android.music.clock
import app.lumiere.android.ui.IosCaption
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.iosClick

/**
 * The iPhone player's controls, for the phone's and the Quest's app: close and
 * picture-in-picture in a frosted capsule at the top left, subtitles and
 * speed, picture and sound at the top right; back ten, play and forward ten
 * plain and white in the middle; at the foot the title over a thin bar that
 * thickens under the finger (the frames there above it), the time gone on the
 * left and the time left on the right, and Episodes and Next beside the title.
 */
@Composable
internal fun PhoneChrome(
    item: Item?, server: Server, trickplay: Trickplay?, playing: Boolean, position: Float, duration: Float, scrubbing: Float?,
    hasNext: Boolean, onScrub: (Float?) -> Unit, onSeek: (Float) -> Unit, onSkip: (Int) -> Unit, onToggle: () -> Unit,
    onBack: () -> Unit, onTracks: () -> Unit, onMenu: () -> Unit, onPip: () -> Unit, onNext: () -> Unit, onEpisodes: (() -> Unit)?,
) {
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
        0f to Color.Black.copy(alpha = 0.5f), 0.22f to Color.Transparent, 0.62f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f)))) {
        Box(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 18.dp, vertical = 12.dp)) {
            Capsule(Modifier.align(Alignment.TopStart)) {
                Glyph(Icons.Default.Close, "Close", onBack)
                Glyph(Icons.Default.PictureInPictureAlt, "Picture in picture", onPip)
            }
            Capsule(Modifier.align(Alignment.TopEnd)) {
                Glyph(Icons.Default.Subtitles, "Audio and subtitles", onTracks)
                Glyph(Icons.Default.Speed, "Speed, picture and sound", onMenu)
            }
            Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(54.dp), verticalAlignment = Alignment.CenterVertically) {
                Plain(Icons.Default.Replay10, "Back ten seconds", 40) { onSkip(-10) }
                Plain(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play", 62, onToggle)
                Plain(Icons.Default.Forward10, "Forward ten seconds", 40) { onSkip(10) }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Column(Modifier.weight(1f)) {
                        item?.let { cur ->
                            if (cur.isEpisode) IosCaption(listOfNotNull(cur.seriesName, cur.episodeLabel).joinToString(" · "),
                                color = Color.White.copy(alpha = 0.7f))
                            Text(cur.name, style = IosType.headline, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (onEpisodes != null || hasNext) Capsule {
                        onEpisodes?.let { Glyph(Icons.AutoMirrored.Filled.PlaylistPlay, "Episodes", it) }
                        if (hasNext) Glyph(Icons.Default.SkipNext, "Next episode", onNext)
                    }
                }
                Spacer(Modifier.height(10.dp))
                Bar(item, server, trickplay, position, duration, scrubbing, onScrub, onSeek)
            }
        }
    }
}

/** The thin bar: tap to jump, drag to scrub, the frames above while dragging. */
@Composable
private fun Bar(item: Item?, server: Server, trickplay: Trickplay?, position: Float, duration: Float, scrubbing: Float?,
                onScrub: (Float?) -> Unit, onSeek: (Float) -> Unit) {
    val thick by animateFloatAsState(if (scrubbing != null) 10f else 5f, label = "thick")
    val shown = scrubbing ?: position
    val total = duration.coerceAtLeast(1f)
    // Read at the moment the finger lifts, not when the drag began.
    val held by rememberUpdatedState(scrubbing)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val trick = trickplay
        if (scrubbing != null && trick != null && duration > 0) ScrubPreview(server, item?.id ?: "", trick, shown, (shown / duration) * maxWidth.value)
        Column {
            Box(Modifier.fillMaxWidth().height(26.dp)
                .pointerInput(duration) { detectTapGestures { o -> onSeek((o.x / size.width).coerceIn(0f, 1f) * duration) } }
                .pointerInput(duration) {
                    detectHorizontalDragGestures(
                        onDragStart = { o -> onScrub((o.x / size.width).coerceIn(0f, 1f) * duration) },
                        onDragEnd = { held?.let(onSeek) ?: onScrub(null) },
                        onDragCancel = { onScrub(null) },
                    ) { c, _ -> onScrub((c.position.x / size.width).coerceIn(0f, 1f) * duration) }
                }
                , contentAlignment = Alignment.CenterStart) {
                Box(Modifier.fillMaxWidth().height(thick.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.25f))) {
                    Box(Modifier.fillMaxWidth((shown / total).coerceIn(0f, 1f)).height(thick.dp).background(Color.White))
                }
            }
            Row(Modifier.fillMaxWidth()) {
                Text(clock(shown.toDouble()), style = IosType.caption, color = Color.White.copy(alpha = 0.75f))
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    chapterAt(item, shown)?.let { Text(it, style = IosType.caption, color = Color.White.copy(alpha = 0.6f), maxLines = 1) }
                }
                Text("-" + clock((duration - shown).toDouble().coerceAtLeast(0.0)), style = IosType.caption, color = Color.White.copy(alpha = 0.75f))
            }
        }
    }
}

/** A frosted capsule holding a few glyphs, as the iPhone player's corners. */
@Composable
private fun Capsule(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.42f)).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically, content = content)
}

@Composable
private fun Glyph(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(42.dp).clip(RoundedCornerShape(50)).iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun Plain(icon: ImageVector, label: String, size: Int, onClick: () -> Unit) {
    Box(Modifier.size((size + 22).dp).clip(RoundedCornerShape(50)).iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(size.dp))
    }
}
