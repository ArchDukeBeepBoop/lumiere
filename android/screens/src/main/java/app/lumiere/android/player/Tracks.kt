package app.lumiere.android.player

import app.lumiere.android.ui.holdsRemote
import app.lumiere.android.ui.frosted

import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.Prefs
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import java.util.Locale

/** One choosable audio or subtitle track, named for people rather than codecs. */
data class TrackChoice(val group: Tracks.Group, val index: Int, val type: Int, val label: String, val language: String?, val selected: Boolean)

@OptIn(UnstableApi::class)
fun trackChoices(player: ExoPlayer, type: Int): List<TrackChoice> =
    player.currentTracks.groups.filter { it.type == type }.flatMap { g ->
        (0 until g.length).filter { g.isTrackSupported(it) }.map { i ->
            val f = g.getTrackFormat(i)
            TrackChoice(g, i, type, describe(f), f.language, g.isTrackSelected(i))
        }
    }

/** "English · 5.1 · Commentary" from a format: language first, then what sets it apart. */
fun describe(f: Format): String {
    val language = f.language?.let { Locale.forLanguageTag(it).displayLanguage.ifEmpty { it } }
    val channels = when (f.channelCount) { 1 -> "Mono"; 2 -> "Stereo"; 6 -> "5.1"; 8 -> "7.1"; else -> null }
    val forced = if (f.selectionFlags and C.SELECTION_FLAG_FORCED != 0) "Forced" else null
    return listOfNotNull(language, f.label?.takeIf { it != language }, channels, forced).joinToString(" · ")
        .ifEmpty { "Track" }
}

fun choose(player: ExoPlayer, choice: TrackChoice?, type: Int) {
    val b = player.trackSelectionParameters.buildUpon()
    if (choice == null) b.setTrackTypeDisabled(type, true)
    else b.setTrackTypeDisabled(type, false).setOverrideForType(TrackSelectionOverride(choice.group.mediaTrackGroup, choice.index))
    player.trackSelectionParameters = b.build()
}

/** The show's remembered choice, put back when its next episode starts. */
fun applyRemembered(player: ExoPlayer, prefs: Prefs, seriesId: String?) {
    val (audio, text) = prefs.tracksFor(seriesId ?: return) ?: return
    audio?.let { lang -> trackChoices(player, C.TRACK_TYPE_AUDIO).firstOrNull { it.language == lang }?.let { choose(player, it, C.TRACK_TYPE_AUDIO) } }
    when (text) {
        null -> Unit
        "off" -> choose(player, null, C.TRACK_TYPE_TEXT)
        else -> trackChoices(player, C.TRACK_TYPE_TEXT).firstOrNull { it.language == text }?.let { choose(player, it, C.TRACK_TYPE_TEXT) }
    }
}

/** Audio on the left, subtitles on the right; a choice is remembered for the show. */
@Composable
fun TrackSheet(player: ExoPlayer, prefs: Prefs, seriesId: String?, note: String? = null, onFind: (() -> Unit)? = null, onSync: (() -> Unit)? = null, onDone: () -> Unit) {
    val audio = trackChoices(player, C.TRACK_TYPE_AUDIO)
    val text = trackChoices(player, C.TRACK_TYPE_TEXT)
    val subtitlesOff = text.none { it.selected }
    // The sheet takes the remote: its first row is focused on opening, and
    // Back closes it rather than the player behind.
    val first = androidx.compose.runtime.remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.activity.compose.BackHandler(onBack = onDone)
    androidx.compose.runtime.LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.7f)),
        contentAlignment = Alignment.Center) {
        Row(Modifier.holdsRemote().widthIn(max = 760.dp).frosted(16).padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            Column("Audio", audio.map { it.label to it.selected }, first) { i ->
                choose(player, audio[i], C.TRACK_TYPE_AUDIO)
                seriesId?.let { prefs.rememberTracks(it, audio = audio[i].language) }
            }
            Column("Subtitles", listOf("Off" to subtitlesOff) + text.map { it.label to it.selected },
                if (audio.isEmpty()) first else null) { i ->
                if (i == 0) choose(player, null, C.TRACK_TYPE_TEXT) else choose(player, text[i - 1], C.TRACK_TYPE_TEXT)
                seriesId?.let { prefs.rememberTracks(it, text = if (i == 0) "off" else text[i - 1].language ?: "off") }
            }
        }
        // No subtitles to choose, or ones that drift: the server can fetch one, or fit them to the dialogue.
        androidx.compose.foundation.layout.Row(Modifier.align(Alignment.BottomCenter).padding(24.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            note?.let { Text(it, color = Color.White) }
            if (onFind != null) LButton(primary = false, onClick = onFind) { Text("Find Subtitles") }
            if (onSync != null) LButton(primary = false, onClick = onSync) { Text("Fix Subtitle Timing") }
            LButton(onClick = onDone) { Text("Done") }
        }
    }
}

@Composable
private fun Column(title: String, rows: List<Pair<String, Boolean>>,
                   focus: androidx.compose.ui.focus.FocusRequester? = null, onPick: (Int) -> Unit) {
    androidx.compose.foundation.layout.Column(Modifier.widthIn(min = 220.dp, max = 340.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 8.dp))
        LazyColumn {
            items(rows.size) { i ->
                val (label, on) = rows[i]
                Text((if (on) "✓  " else "    ") + label, style = MaterialTheme.typography.titleMedium,
                    color = if (on) Palette.accent else Palette.textPrimary,
                    modifier = Modifier.fillMaxWidth()
                        .then(if (i == 0 && focus != null) Modifier.focusRequester(focus) else Modifier)
                        .focusCard { onPick(i) }.padding(10.dp))
            }
        }
    }
}
