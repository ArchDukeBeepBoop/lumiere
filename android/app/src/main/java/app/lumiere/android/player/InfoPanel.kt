package app.lumiere.android.player

import app.lumiere.android.ui.holdsRemote
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.api.Item
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.frosted

/**
 * tvOS's swipe-down panel: one row of pills across the top of the film —
 * Info, Chapters, Subtitles & Audio, Episodes, More — and the chosen one's
 * content under it. Down from a playing film opens it; Up or Back closes it.
 */
@Composable
fun InfoPanel(item: Item?, clock: Clock, startTab: String = "Info", onTracks: () -> Unit, onMenu: () -> Unit, onEpisodes: (() -> Unit)?, onClose: () -> Unit) {
    var tab by remember { mutableStateOf(startTab) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler(onBack = onClose)
    val chapters = item?.chapters.orEmpty()
    Column(Modifier.holdsRemote().fillMaxWidth().padding(28.dp).frosted().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            TvPill({ tab = "Info" }, Modifier.focusRequester(first), selected = tab == "Info") { Text("Info") }
            if (chapters.isNotEmpty()) TvPill({ tab = "Chapters" }, selected = tab == "Chapters") { Text("Chapters") }
            TvPill({ onClose(); onTracks() }) { Text("Subtitles & Audio") }
            if (onEpisodes != null) TvPill({ onClose(); onEpisodes() }) { Text("Episodes") }
            TvPill({ onClose(); onMenu() }) { Text("Speed & Picture") }
        }
        when (tab) {
            "Info" -> item?.let { it ->
                Column(Modifier.widthIn(max = 820.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(if (it.isEpisode) "${it.seriesName ?: ""} · ${it.episodeLabel ?: ""} · ${it.name}" else it.name,
                        style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    it.overview?.let { o -> Text(o, style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary, maxLines = 4) }
                    // Who is in it — the first names, as Apple's info card lists them.
                    if (it.people.isNotEmpty()) Text("With " + it.people.take(5).joinToString(", ") { p -> p.name },
                        style = MaterialTheme.typography.labelLarge, color = Palette.textSecondary, maxLines = 1)
                }
            }
            "Chapters" -> LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(chapters) { c ->
                    val m = (c.startSeconds / 60).toInt()
                    TvPill({ clock.seek(c.startSeconds); onClose() }) {
                        Text("${m / 60}:${"%02d".format(m % 60)}  ${c.name ?: ""}".trim())
                    }
                }
            }
        }
    }
}
