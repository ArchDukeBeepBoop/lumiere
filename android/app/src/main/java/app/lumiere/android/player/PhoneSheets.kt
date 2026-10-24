package app.lumiere.android.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.Prefs
import app.lumiere.android.ui.IosCaption
import app.lumiere.android.ui.IosSegmented
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette

/** The iPhone player's sheet: dark, rounded at the top, rising from the foot, a tap outside closing it. */
@Composable
private fun Sheet(title: String, onDone: () -> Unit, content: @Composable () -> Unit) {
    BackHandler(onBack = onDone)
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f))
        .clickable(remember { MutableInteractionSource() }, null, onClick = onDone), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().heightIn(max = 520.dp)
            .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)).background(Color(0xF21C1C1E))
            .clickable(remember { MutableInteractionSource() }, null) {}.navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 10.dp, top = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = IosType.headline, color = Color.White, modifier = Modifier.weight(1f))
                Text("Done", style = IosType.headline, color = Palette.accent,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onDone).padding(horizontal = 10.dp, vertical = 6.dp))
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) { content() }
        }
    }
}

/** A grouped list of choices, a tick beside the chosen one. */
@Composable
private fun Choices(header: String, rows: List<Pair<String, Boolean>>, onPick: (Int) -> Unit) {
    if (rows.isEmpty()) return
    Column(Modifier.padding(horizontal = 14.dp)) {
        IosCaption(header, Modifier.padding(start = 6.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color(0xFF2C2C2E))) {
            rows.forEachIndexed { i, (label, on) ->
                Row(Modifier.fillMaxWidth().clickable { onPick(i) }.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(label, style = IosType.body, color = Color.White, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (on) Icon(Icons.Default.Check, "Chosen", tint = Palette.accent, modifier = Modifier.size(20.dp))
                }
                if (i < rows.lastIndex) HorizontalDivider(Modifier.padding(start = 14.dp), 0.5.dp, Color.White.copy(alpha = 0.1f))
            }
        }
    }
}

/** Audio and Subtitles as the iPhone's player lists them; a choice is remembered for the show. */
@Composable
internal fun PhoneTrackSheet(player: ExoPlayer, prefs: Prefs, seriesId: String?, note: String?, onFind: (() -> Unit)?, onSync: (() -> Unit)?, onDone: () -> Unit) {
    var tick by remember { mutableIntStateOf(0) }
    tick.let { }
    val audio = trackChoices(player, C.TRACK_TYPE_AUDIO)
    val text = trackChoices(player, C.TRACK_TYPE_TEXT)
    Sheet("Audio & Subtitles", onDone) {
        Choices("Audio", audio.map { it.label to it.selected }) { i ->
            choose(player, audio[i], C.TRACK_TYPE_AUDIO); seriesId?.let { prefs.rememberTracks(it, audio = audio[i].language) }; tick++
        }
        Choices("Subtitles", listOf("Off" to text.none { it.selected }) + text.map { it.label to it.selected }) { i ->
            if (i == 0) choose(player, null, C.TRACK_TYPE_TEXT) else choose(player, text[i - 1], C.TRACK_TYPE_TEXT)
            seriesId?.let { prefs.rememberTracks(it, text = if (i == 0) "off" else text[i - 1].language ?: "off") }; tick++
        }
        val actions = listOfNotNull(onFind?.let { "Find Subtitles" to it }, onSync?.let { "Fix Subtitle Timing" to it })
        if (actions.isNotEmpty()) Choices("Subtitles from the Mac", actions.map { it.first to false }) { actions[it].second() }
        note?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary, modifier = Modifier.padding(horizontal = 20.dp)) }
    }
}

/** Speed, picture, subtitles' look, sound and the sleep timer, as segmented rows in one sheet. */
@Composable
internal fun PhoneQuickSheet(player: ExoPlayer, prefs: Prefs, onTracks: () -> Unit, onClose: () -> Unit) {
    var speed by remember { mutableIntStateOf((player.playbackParameters.speed * 100).toInt()) }
    var sleep by remember { mutableIntStateOf(when { SleepTimer.endOfEpisode -> 1; SleepTimer.until != null -> 2; else -> 0 }) }
    Sheet("Playback", onClose) {
        Choices("Audio & Subtitles", listOf("Choose Audio and Subtitles" to false)) { onClose(); onTracks() }
        Seg("Speed", listOf(75, 100, 125, 150, 200).map { "${it / 100.0}×".replace(".0×", "×") }, listOf(75, 100, 125, 150, 200).indexOf(speed)) {
            speed = listOf(75, 100, 125, 150, 200)[it]; player.setPlaybackSpeed(speed / 100f)
        }
        Seg("Picture", listOf("Fit", "Fill"), if (prefs.fillsScreen) 1 else 0) { prefs.fillsScreen = it == 1 }
        Seg("Subtitle Size", listOf("S", "M", "L", "XL"), prefs.subtitleSize) { prefs.subtitleSize = it }
        Seg("Subtitle Look", listOf("Outline", "Shadow", "Box"), prefs.subtitleStyle) { prefs.subtitleStyle = it }
        Seg("Dialogue Boost", listOf("Off", "+3", "+6", "+9"), prefs.dialogueBoost / 3) { prefs.dialogueBoost = it * 3 }
        Seg("Night Sound", listOf("Off", "On"), if (prefs.nightSound) 1 else 0) { prefs.nightSound = it == 1 }
        Seg("Sleep Timer", listOf("Off", "Episode", "30 m", "60 m"), sleep) {
            sleep = it
            SleepTimer.endOfEpisode = it == 1
            SleepTimer.until = when (it) { 2 -> System.currentTimeMillis() + 30 * 60_000L; 3 -> System.currentTimeMillis() + 60 * 60_000L; else -> null }
        }
    }
}

@Composable
private fun Seg(title: String, options: List<String>, selected: Int, onPick: (Int) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp)) {
        IosCaption(title, Modifier.padding(start = 6.dp, bottom = 6.dp))
        IosSegmented(options, selected.coerceAtLeast(0), onPick)
        Spacer(Modifier.size(0.dp))
    }
}
