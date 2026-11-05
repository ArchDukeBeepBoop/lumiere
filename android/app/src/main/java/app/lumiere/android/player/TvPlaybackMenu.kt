package app.lumiere.android.player

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.Prefs
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.frosted
import app.lumiere.android.ui.holdsRemote
import app.lumiere.android.ui.pillTint

/** One setting of the menu: its name, its choices, which is current, and how to choose. */
private class Setting(val title: String, val options: List<Int>, val current: () -> Int, val name: (Int) -> String, val set: (Int) -> Unit)

/**
 * The TV player's settings as tvOS draws its playback menu: a frosted popover at
 * the right, one row per setting with its current value and a chevron; choosing a
 * row opens its options with a tick beside the current one. Back goes up a level,
 * then closes.
 */
@Composable
fun TvPlaybackMenu(player: ExoPlayer, prefs: Prefs, onTracks: () -> Unit, onClose: () -> Unit) {
    var speed by remember { mutableIntStateOf((player.playbackParameters.speed * 100).toInt()) }
    val settings = listOf(
        Setting("Speed", listOf(75, 100, 125, 150, 200), { speed }, { "${it / 100.0}×".replace(".0×", "×") }) { speed = it; player.setPlaybackSpeed(it / 100f) },
        Setting("Picture", listOf(0, 1), { if (prefs.fillsScreen) 1 else 0 }, { if (it == 1) "Fill" else "Fit" }) { prefs.fillsScreen = it == 1 },
        Setting("Picture Tone", listOf(0, 1, 2), { prefs.pictureTone }, { listOf("Neutral", "Warmer", "Cooler")[it] }) { prefs.pictureTone = it },
        Setting("Lamp", listOf(0, 1), { if (prefs.lampBright) 1 else 0 }, { if (it == 1) "Brightest" else "As Set" }) { prefs.lampBright = it == 1 },
        Setting("Subtitle Size", listOf(0, 1, 2, 3), { prefs.subtitleSize }, { listOf("Small", "Medium", "Large", "Extra Large")[it] }) { prefs.subtitleSize = it },
        Setting("Subtitle Look", listOf(0, 1, 2), { prefs.subtitleStyle }, { listOf("Outline", "Shadow", "Dark Box")[it] }) { prefs.subtitleStyle = it },
        Setting("Dialogue Boost", listOf(0, 3, 6, 9), { prefs.dialogueBoost }, { if (it == 0) "Off" else "+$it dB" }) { prefs.dialogueBoost = it },
        Setting("Night Sound", listOf(0, 1), { if (prefs.nightSound) 1 else 0 }, { if (it == 1) "On" else "Off" }) { prefs.nightSound = it == 1 },
        Setting("Sleep Timer", listOf(0, -1, 30, 60, 90),
            { when {
                SleepTimer.endOfEpisode -> -1
                // A timer running: the choice nearest the minutes left.
                SleepTimer.until != null -> listOf(30, 60, 90).minBy { m -> kotlin.math.abs(m - (SleepTimer.until!! - System.currentTimeMillis()) / 60_000L) }
                else -> 0
            } },
            { when (it) { 0 -> "Off"; -1 -> "End of Episode"; else -> "$it Minutes" } }) {
            SleepTimer.endOfEpisode = it == -1
            SleepTimer.until = if (it > 0) System.currentTimeMillis() + it * 60_000L else null
        },
    )
    var open by remember { mutableStateOf<Setting?>(null) }
    var stats by remember { mutableStateOf(false) }
    val first = remember(open, stats) { FocusRequester() }
    LaunchedEffect(open, stats) { kotlinx.coroutines.delay(50); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler { if (open != null) open = null else if (stats) stats = false else onClose() }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.CenterEnd) {
        Column(Modifier.holdsRemote().padding(end = 36.dp).width(400.dp).heightIn(max = 560.dp).frosted(22).padding(10.dp)) {
            Text(open?.title ?: if (stats) "Playback Info" else "Playback", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                color = Palette.textSecondary, modifier = Modifier.padding(start = 14.dp, top = 6.dp, bottom = 8.dp))
            val o = open
            LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (stats) {
                    item { PlaybackInfo(player, Modifier.focusRequester(first)) }
                } else if (o == null) {
                    item {
                        TvPill({ onClose(); onTracks() }, Modifier.fillMaxWidth().focusRequester(first), shape = RoundedCornerShape(12.dp)) {
                            Text("Audio & Subtitles", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                            app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.chevronRight, tint = pillTint(Palette.textMuted))
                        }
                    }
                    itemsIndexed(settings) { _, st ->
                        TvPill({ open = st }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                            Text(st.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                            Text(st.name(st.current()), style = MaterialTheme.typography.bodyMedium, color = pillTint(Palette.textSecondary))
                            Spacer(Modifier.width(8.dp))
                            app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.chevronRight, tint = pillTint(Palette.textMuted))
                        }
                    }
                    // For diagnostics, last as tvOS keeps it: what the projector is actually decoding.
                    item {
                        TvPill({ stats = true }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                            Text("Playback Info", style = MaterialTheme.typography.titleMedium, color = pillTint(Palette.textSecondary), modifier = Modifier.weight(1f))
                            app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.chevronRight, tint = pillTint(Palette.textMuted))
                        }
                    }
                } else {
                    val now = o.current()
                    itemsIndexed(o.options) { _, v ->
                        TvPill({ o.set(v); open = null }, Modifier.fillMaxWidth().then(if (v == now) Modifier.focusRequester(first) else Modifier),
                            shape = RoundedCornerShape(12.dp)) {
                            // The tick sits before the current choice, as Apple's menus mark it.
                            Box(Modifier.size(22.dp)) { if (v == now) app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.check, size = 18.dp) }
                            Spacer(Modifier.width(8.dp))
                            Text(o.name(v), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

/** The stream as the projector decodes it, read once a second while shown. */
@Composable
internal fun PlaybackInfo(player: ExoPlayer, modifier: Modifier) {
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1_000); tick++ } }
    tick
    val v = player.videoFormat
    val a = player.audioFormat
    val codec = { f: androidx.media3.common.Format? -> (f?.codecs ?: f?.sampleMimeType?.substringAfter('/'))?.uppercase() ?: "—" }
    val rows = listOf(
        "Resolution" to (v?.let { "${it.width} × ${it.height}" + (if (it.frameRate > 0) " · ${"%.3g".format(it.frameRate)} fps" else "") } ?: "—"),
        "Video" to (codec(v) + (v?.bitrate?.takeIf { it > 0 }?.let { " · ${"%.1f".format(it / 1_000_000.0)} Mb/s" } ?: "")),
        "HDR" to (v?.colorInfo?.let { when (it.colorTransfer) { androidx.media3.common.C.COLOR_TRANSFER_ST2084 -> "HDR10 / PQ"
            androidx.media3.common.C.COLOR_TRANSFER_HLG -> "HLG"; else -> "SDR" } } ?: "SDR"),
        "Audio" to (codec(a) + (a?.channelCount?.takeIf { it > 0 }?.let { " · $it ch" } ?: "")),
        "Buffer" to "${((player.bufferedPosition - player.currentPosition).coerceAtLeast(0) / 1000)} s ahead",
        "Dropped Frames" to "${player.videoDecoderCounters?.droppedBufferCount ?: 0}",
    )
    // Focusable so the remote has somewhere to rest; Back returns to the menu.
    Column(modifier.fillMaxWidth().focusable().padding(horizontal = 14.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { (k, value) ->
            Row {
                Text(k, style = app.lumiere.android.ui.TvType.meta, modifier = Modifier.weight(1f))
                Text(value, style = app.lumiere.android.ui.TvType.body)
            }
        }
    }
}
