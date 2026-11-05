package app.lumiere.android.tv

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.Prefs
import app.lumiere.android.QuestPlaces
import app.lumiere.android.ui.Palette

/**
 * Settings in the headset, as Horizon OS's own Settings: Headset first, then only
 * what a headset uses. The server's and the Mac's work (libraries, folders, the
 * setup guide, diagnostics) and the projector's (lamp, tone, screensaver, remote
 * ticks, phone pairing) are left to them and the TV.
 */
internal fun questHeadset(context: Context, p: Prefs): Category {
    // The theater's own store (spatial/ScreenPlace), read again each time a film starts.
    val screen = context.getSharedPreferences("quest.screen", Context.MODE_PRIVATE)
    return Category("Headset", listOf(
        Opt.Pick("Where to watch", "The place round you when a film plays. Also on the film's bar, as it plays.",
            QuestPlaces.all.map { it.second }, { QuestPlaces.chosen(context) }) { QuestPlaces.choose(context, it) },
        Opt.Pick("Screen size", "How large a film's screen is in the place. Also on the film's bar.", SIZES,
            { screen.getInt("size", 1).coerceIn(0, SIZES.lastIndex) }) { screen.edit().putInt("size", it).apply() },
        Opt.Pick("Seat", "How far from the screen you sit.", SEATS,
            { screen.getInt("seat", 1).coerceIn(0, SEATS.lastIndex) }) { screen.edit().putInt("seat", it).apply() },
        Opt.Pick("TV Mode size", "The screen on your wall, as a TV's diagonal: up to 200″, or as large as the wall holds.", TV_SIZES,
            { screen.getInt("tvSize", 4).coerceIn(0, TV_SIZES.lastIndex) }) { screen.edit().putInt("tvSize", it).apply() },
        Opt.Action("Leave TV Mode", "A screen hung on a wall of your room floats again, before you.") {
            screen.edit().remove("mounted").apply() },
        Opt.Toggle("Light follows the film", "A place's light takes on the colours of the film's artwork.",
            { p.questFilmLight }) { p.questFilmLight = it },
        Opt.Toggle("Pictures behind Home", "Off: Home sits on Lumiere's colours. On: behind the titles' pictures, as on the TV.",
            { p.questArtBackdrop }) { p.questArtBackdrop = it },
        Opt.Toggle("Reduce motion", "No tilt or drifting, and quick fades: easier on the eyes in a headset.",
            { p.reduceMotion }) { p.reduceMotion = it },
    ))
}

private val SIZES = listOf("Small", "Medium", "Large", "Very Large", "Cinema")
private val SEATS = listOf("Near", "Middle", "Far")
// TvMode.INCHES (spatial), which this shared code can't see.
private val TV_SIZES = listOf(32, 43, 50, 55, 65, 75, 85, 98, 100, 120, 150, 200).map { "$it″" }

/** Left to the Mac, the server or the TV. */
private val NOT_IN_HEADSET = setOf(
    "Open the Setup Guide", "Libraries & Folders", "Send diagnostics to the Mac", "View diagnostics",
    "Picture tone", "Warmer picture for films", "Lamp at full brightness during films", "Darker menus from 10 pm to 6 am",
    "Screensaver after", "Sound as the remote moves", "Tabs along the top", "Immersive Home (sample data)", "Rows on Home",
    "Show the remote tour again", "Phone as remote", "Pair a phone now", "Forget paired phones", "Reduce motion",
)

/** The TV's categories, trimmed for the headset and renamed where the TV's names don't fit it. */
internal fun questArrange(all: List<Category>): List<Category> {
    val kept = all.map { c -> Category(RENAME[c.name] ?: c.name, c.options.filter { it.title !in NOT_IN_HEADSET || (c.name == "Headset") }) }
    val changes = kept.firstOrNull { it.name == "Your Setup" }?.options.orEmpty()
    val rest = kept.filter { it.name != "Your Setup" && it.name != "Headset" && it.options.isNotEmpty() }
        .map { if (it.name == "Account") Category(it.name, it.options + changes) else it }
    return kept.filter { it.name == "Headset" } + rest
}

private val RENAME = mapOf("Picture & Text" to "Text & Comfort", "This Device" to "This Headset")

/** One setting as Horizon OS draws it: a 56 dp row, its note always shown, a switch for on and off. */
@Composable
internal fun QuestOptionRow(o: Opt, open: () -> Unit) {
    app.lumiere.android.ui.TvPill({
        when (o) { is Opt.Toggle -> o.set(!o.get()); is Opt.Pick -> open(); is Opt.Action -> o.run(); is Opt.Custom -> Unit }
    }, Modifier.fillMaxWidth(), selected = true, shape = RoundedCornerShape(18.dp), focusedScale = 1.01f) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 16.dp)) {
                Text(o.title, style = MaterialTheme.typography.titleMedium)
                if (o.note.isNotEmpty()) Text(o.note, style = MaterialTheme.typography.labelMedium,
                    color = androidx.compose.material3.LocalContentColor.current.copy(alpha = 0.65f))
            }
            when (o) {
                is Opt.Toggle -> Switch(o.get(), { o.set(it) }, colors = SwitchDefaults.colors(checkedTrackColor = Palette.accent))
                is Opt.Pick -> Text((o.labels.getOrNull(o.get()) ?: "") + "  ›", color = app.lumiere.android.ui.pillTint(Palette.accent))
                is Opt.Action -> app.lumiere.android.ui.Mark(app.lumiere.android.ui.Symbols.chevronRight, tint = app.lumiere.android.ui.pillTint(Palette.textMuted))
                is Opt.Custom -> Unit
            }
        }
    }
}

/** Home's rows for a hand rather than a remote: up and down arrows, and a dot that switches a row on or off. */
@Composable
internal fun QuestHomeOrder(p: Prefs) {
    val order = p.tvRowOrder
    Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(2.dp)) {
        order.forEachIndexed { i, key ->
            val hidden = key in p.tvRowsHidden
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                app.lumiere.android.ui.TvPill({ p.tvRowsHidden = if (hidden) p.tvRowsHidden - key else p.tvRowsHidden + key }) {
                    Text(if (hidden) "○" else "●", color = if (hidden) Palette.textMuted else Palette.accent) }
                Text(Prefs.TV_ROW_NAMES[key] ?: key, Modifier.weight(1f).padding(horizontal = 8.dp), style = MaterialTheme.typography.titleMedium,
                    color = if (hidden) Palette.textMuted else Palette.textPrimary)
                if (i > 0) app.lumiere.android.ui.TvPill({ p.tvRowOrder = order.toMutableList().apply { add(i - 1, removeAt(i)) } }) { Text("↑") }
                if (i < order.lastIndex) app.lumiere.android.ui.TvPill({ p.tvRowOrder = order.toMutableList().apply { add(i + 1, removeAt(i)) } }) { Text("↓") }
            }
        }
    }
}
