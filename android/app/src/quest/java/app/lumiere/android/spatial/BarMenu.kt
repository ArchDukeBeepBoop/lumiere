package app.lumiere.android.spatial

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.player.Entry
import app.lumiere.android.player.Theater
import app.lumiere.android.ui.Palette

/**
 * The player's menus in the room — Audio, Subtitles, More — as a small glass
 * list just above the film's bar, as Apple's player opens its own above its
 * controls: the same choices as the TV's popover (Theater.entries), never
 * the window. A row with a value opens its list in place; the top row goes
 * back up, and Close (or B) shuts it.
 */
object BarMenu {
    const val WIDTH_M = 0.34f
    const val HEIGHT_M = 0.4f
    const val WIDTH_DP = 400f
    const val HEIGHT_DP = 470f

    /** The menu open ("Audio", "Subtitles", "More"), or null. */
    var kind by mutableStateOf<String?>(null)
    /** Lists opened from rows, deepest last, with their titles. */
    private var levels by mutableStateOf<List<Pair<String, () -> List<Entry>>>>(emptyList())
    /** Bumped by every choice: the lists are built afresh, so the tick moves to what was chosen. */
    private var version by androidx.compose.runtime.mutableIntStateOf(0)

    fun open(k: String) { levels = emptyList(); kind = if (kind == k) null else k }
    fun close() { kind = null; levels = emptyList() }
    /** B on a controller: up a level, then shut. True when it did something. */
    fun back(): Boolean {
        if (kind == null) return false
        if (levels.isNotEmpty()) levels = levels.dropLast(1) else close()
        return true
    }

    @Composable
    fun Panel() {
        val k = kind ?: return
        @Suppress("UNUSED_EXPRESSION") version
        val (title, build) = levels.lastOrNull() ?: (k to { Theater.entries?.invoke(k).orEmpty() })
        val entries = build()
        Column(Modifier.fillMaxSize().clip(RoundedCornerShape(28.dp)).background(Palette.canvas.copy(alpha = 0.92f)).padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (levels.isEmpty()) title else "‹  $title", Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                    .clickable(enabled = levels.isNotEmpty()) { back() }.padding(10.dp),
                    style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary))
                Row(Modifier.clip(RoundedCornerShape(12.dp)).clickable { close() }.padding(10.dp)) {
                    Text("Close", style = TextStyle(fontSize = 16.sp, color = Palette.textSecondary))
                }
            }
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                entries.forEach { e -> EntryRow(e) }
            }
        }
    }

    @Composable
    private fun EntryRow(e: Entry) {
        val row = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
        val text = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium, color = Palette.textPrimary)
        when (e) {
            is Entry.Caption -> Text(e.text.uppercase(), Modifier.padding(start = 12.dp, top = 12.dp, bottom = 4.dp),
                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted, letterSpacing = 1.sp))
            is Entry.Choice -> Row(row.clickable { e.act(); version++; if (e.closes) close() }.padding(12.dp)) {
                Text(if (e.on) "✓" else "", Modifier.padding(end = 10.dp), style = text)
                Text(e.label, style = text)
            }
            is Entry.Link -> Row(row.clickable { levels = levels + (e.label to e.open) }.padding(12.dp)) {
                Text(e.label, Modifier.weight(1f), style = text)
                e.value?.let { Text("$it  ›", style = TextStyle(fontSize = 15.sp, color = Palette.textSecondary)) }
            }
            is Entry.Action -> Row(row.clickable { close(); e.act() }.padding(12.dp)) { Text(e.label, style = text) }
            is Entry.Custom -> e.content(Modifier.padding(12.dp))
        }
    }
}
