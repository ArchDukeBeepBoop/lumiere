package app.lumiere.android.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Crop169
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Panorama
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.Stage
import app.lumiere.android.music.clock
import app.lumiere.android.player.Theater
import kotlinx.coroutines.delay

/**
 * The Theater's transport: a bar of glass that floats near your hands while
 * a film plays on its own screen — back and forward ten seconds, play and
 * pause, a scrubber with the film's frames floating above it as you drag,
 * and the screen itself: smaller, larger, curved or flat, where it plays.
 * "More" brings the window's own player screen (tracks, info) in front.
 * It shows when the film is paused or you've just touched anything, and
 * steps away a few seconds later.
 */
@Composable
fun TheaterBar() = WithAppImages {
    LumiereTheme {
        val c = Theater.controls ?: return@LumiereTheme
        var position by remember(c) { mutableDoubleStateOf(c.clock.now()) }
        var duration by remember(c) { mutableDoubleStateOf(c.clock.duration()) }
        var playing by remember(c) { mutableStateOf(c.player.isPlaying) }
        var scrubbing by remember(c) { mutableStateOf<Float?>(null) }
        LaunchedEffect(c) {
            while (true) {
                position = c.clock.now(); duration = c.clock.duration(); playing = c.player.isPlaying
                delay(250)
            }
        }
        fun touch(action: () -> Unit) { Theater.poke(); action() }
        Column(Modifier.fillMaxSize().spatialGlass(30).padding(horizontal = 24.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(c.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    c.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.textSecondary, maxLines = 1) }
                }
                val shown = scrubbing?.toDouble() ?: position
                Text("${clock(shown)} / ${clock(duration)}", color = Palette.textSecondary)
            }
            Slider(
                value = (scrubbing ?: position.toFloat()).coerceIn(0f, duration.toFloat().coerceAtLeast(1f)),
                valueRange = 0f..duration.toFloat().coerceAtLeast(1f),
                onValueChange = { v ->
                    Theater.poke(); scrubbing = v
                    c.trickplay()?.let { t -> Floating.scrub = Floating.Scrub(c.server, c.itemId, t, v) }
                },
                onValueChangeFinished = {
                    scrubbing?.let { c.clock.seek(it.toDouble()) }
                    scrubbing = null; Floating.scrub = null
                },
                colors = SliderDefaults.colors(thumbColor = Palette.accent, activeTrackColor = Palette.accent),
                modifier = Modifier.fillMaxWidth(),
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GlassButton(Icons.Default.Replay10, "Back 10 seconds") { touch { c.clock.seek((c.clock.now() - 10).coerceAtLeast(0.0)) } }
                GlassButton(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play",
                    chosen = true, size = 56.dp) { touch { if (c.player.isPlaying) c.player.pause() else c.player.play() } }
                GlassButton(Icons.Default.Forward10, "Forward 10 seconds") { touch { c.clock.seek(c.clock.now() + 10) } }
                Spacer(Modifier.weight(1f))
                GlassButton(Icons.Default.ZoomOut, "Smaller screen") { touch { Stage.smaller() } }
                GlassButton(Icons.Default.ZoomIn, "Larger screen") { touch { Stage.larger() } }
                GlassButton(if (Stage.curved) Icons.Default.Crop169 else Icons.Default.Panorama,
                    if (Stage.curved) "Flat screen" else "Curved screen") { touch { Stage.toggleCurve() } }
                GlassButton(placeIcon(Stage.place), "Watch in ${Stage.place.label}", caption = placeCaption(Stage.place)) { touch { Stage.nextPlace() } }
                Spacer(Modifier.width(10.dp))
                GlassButton(Icons.Default.Tune, "Tracks and info", chosen = Theater.windowAsked) { touch { Theater.windowAsked = !Theater.windowAsked } }
                GlassButton(Icons.Default.Close, "Stop watching") { touch { c.exit() } }
            }
        }
    }
}

/**
 * The Theater's captions: the film's subtitles, drawn on a clear panel over
 * the foot of its screen at the screen's own scale — text the player's
 * cues carry, or the pictures of image subtitles.
 */
@Composable
fun TheaterCaptions() {
    LumiereTheme {
        val cues = Theater.cues
        if (cues.isEmpty()) return@LumiereTheme
        Box(Modifier.fillMaxSize().padding(bottom = 24.dp), contentAlignment = Alignment.BottomCenter) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                cues.forEach { cue ->
                    val bitmap = cue.bitmap
                    val text = cue.text?.toString()?.trim()
                    when {
                        bitmap != null -> Image(bitmap.asImageBitmap(), null,
                            Modifier.fillMaxWidth(if (cue.size > 0f && cue.size <= 1f) cue.size else 0.6f))
                        !text.isNullOrEmpty() -> Text(text, textAlign = TextAlign.Center,
                            style = TextStyle(fontSize = 46.sp, color = Color.White, lineHeight = 54.sp,
                                shadow = Shadow(Color.Black, blurRadius = 6f)),
                            modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 18.dp, vertical = 6.dp))
                    }
                }
            }
        }
    }
}
