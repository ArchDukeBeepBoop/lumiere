package app.lumiere.android.player

import app.lumiere.android.ui.holdsRemote
import androidx.compose.foundation.layout.size
import app.lumiere.android.ui.frosted

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.Prefs
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.imageFor
import app.lumiere.android.ui.CardShape
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/** Stop after this episode, or after a number of minutes. */
object SleepTimer {
    var endOfEpisode = false
    var until: Long? = null
    fun label(): String = when {
        endOfEpisode -> "End of episode"
        until != null -> "${((until!! - System.currentTimeMillis()) / 60_000).coerceAtLeast(0)} min left"
        else -> "Off"
    }
}

/**
 * The Menu button's strip during playback: speed, picture, subtitles, sound
 * and the sleep timer, without leaving the film.
 */
@Composable
fun QuickPanel(player: ExoPlayer, prefs: Prefs, onTracks: () -> Unit, onClose: () -> Unit) {
    val first = remember { FocusRequester() }
    var speed by remember { mutableIntStateOf(((player.playbackParameters.speed) * 100).toInt()) }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)), contentAlignment = Alignment.BottomCenter) {
        androidx.activity.compose.BackHandler(onBack = onClose)
        LazyColumn(Modifier.holdsRemote().padding(32.dp).frosted(16).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LButton(onClick = { onClose(); onTracks() }, modifier = Modifier.focusRequester(first)) { Text("Audio & Subtitles") }
                LButton(primary = false, onClick = onClose) { Text("Close") }
            } }
            item { Line("Speed", listOf(75, 100, 125, 150, 200), speed, { "${it / 100.0}×".replace(".0×", "×") }) {
                speed = it; player.setPlaybackSpeed(it / 100f) } }
            item { Line("Picture", listOf(0, 1), if (prefs.fillsScreen) 1 else 0, { if (it == 1) "Fill" else "Fit" }) {
                prefs.fillsScreen = it == 1 } }
            item { Line("Picture tone", listOf(0, 1, 2), prefs.pictureTone, { listOf("Neutral", "Warmer", "Cooler")[it] }) {
                prefs.pictureTone = it } }
            item { Line("Lamp", listOf(0, 1), if (prefs.lampBright) 1 else 0, { if (it == 1) "Brightest" else "As set" }) {
                prefs.lampBright = it == 1 } }
            item { Line("Subtitle size", listOf(0, 1, 2, 3), prefs.subtitleSize,
                { listOf("Small", "Medium", "Large", "Extra large")[it] }) { prefs.subtitleSize = it } }
            item { Line("Subtitle look", listOf(0, 1, 2), prefs.subtitleStyle,
                { listOf("Outline", "Shadow", "Dark box")[it] }) { prefs.subtitleStyle = it } }
            item { Line("Dialogue boost", listOf(0, 3, 6, 9), prefs.dialogueBoost, { if (it == 0) "Off" else "+$it dB" }) {
                prefs.dialogueBoost = it } }
            item { Line("Night sound", listOf(0, 1), if (prefs.nightSound) 1 else 0, { if (it == 1) "On" else "Off" }) {
                prefs.nightSound = it == 1 } }
            item {
                val current = when { SleepTimer.endOfEpisode -> -1; SleepTimer.until != null -> 1; else -> 0 }
                Line("Sleep", listOf(0, -1, 30, 60, 90), current, { when (it) { 0 -> "Off"; -1 -> "End of episode"; else -> "$it min" } }) {
                    SleepTimer.endOfEpisode = it == -1
                    SleepTimer.until = if (it > 0) System.currentTimeMillis() + it * 60_000L else null
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

@Composable
private fun Line(title: String, options: List<Int>, selected: Int, name: (Int) -> String, pick: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.width(150.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(options.size) { i -> LChip(options[i] == selected, { pick(options[i]) }, { Text(name(options[i])) }) }
        }
    }
}

/**
 * In the credits, the next episode's still and a countdown — the Mac's Up
 * Next. OK plays it now; Back keeps watching the credits.
 */
@Composable
fun UpNextCard(next: Item, server: Server, counting: Boolean, onPlay: () -> Unit, onDismiss: () -> Unit) {
    val focus = remember { FocusRequester() }
    var left by remember(next.id) { mutableIntStateOf(10) }
    LaunchedEffect(next.id, counting) {
        if (!counting) return@LaunchedEffect
        while (left > 0) { delay(1000); left-- }
        onPlay()
    }
    Box(Modifier.fillMaxSize().padding(start = 32.dp, top = 32.dp, end = 32.dp, bottom = 132.dp), contentAlignment = Alignment.BottomEnd) {
        Column(Modifier.width(340.dp).frosted(14).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (counting) "Up Next in $left" else "Up Next", style = MaterialTheme.typography.labelMedium, color = Palette.accent)
            AsyncImage(imageFor(next, server, CardShape.Wide, 640), null, contentScale = ContentScale.Crop,
                modifier = Modifier.aspectRatio(16f / 9f).background(Palette.surfaceRaised, RoundedCornerShape(8.dp)))
            Text(listOfNotNull(next.episodeLabel, next.name).joinToString(" · "), style = MaterialTheme.typography.titleMedium,
                maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // tvOS's ring: the countdown drawn round the play mark, not just a number.
                LButton(onClick = onPlay, modifier = Modifier.focusRequester(focus)) {
                    if (counting) androidx.compose.material3.CircularProgressIndicator(progress = { left / 10f },
                        modifier = Modifier.size(18.dp), strokeWidth = 2.dp,
                        color = androidx.compose.material3.LocalContentColor.current, trackColor = androidx.compose.ui.graphics.Color.Transparent)
                    else Text("▶")
                    Text("  Play Now")
                }
                LButton(primary = false, onClick = onDismiss) { Text("Watch Credits") }
            }
        }
    }
    LaunchedEffect(next.id) { runCatching { focus.requestFocus() } }
}
