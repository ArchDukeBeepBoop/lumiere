package app.lumiere.android.player

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.Prefs
import app.lumiere.android.ui.Mark
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.Symbols
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.frosted
import app.lumiere.android.ui.holdsRemote
import app.lumiere.android.ui.ignoreHeldOk
import app.lumiere.android.ui.pillTint

/** One line of a popover menu. */
internal sealed interface Entry {
    /** A small heading over a section. */
    data class Caption(val text: String) : Entry
    /** A choice with a tick when it is the current one; [closes] the menu when chosen. */
    data class Choice(val label: String, val on: Boolean, val closes: Boolean = true, val act: () -> Unit) : Entry
    /** A row that opens a further list, its current value at the right. */
    data class Link(val label: String, val value: String?, val open: () -> List<Entry>) : Entry
    /** A row that does something else, a sheet or a screen. */
    data class Action(val label: String, val act: () -> Unit) : Entry
    /** Free content, Playback Info's figures. */
    data class Custom(val content: @Composable (Modifier) -> Unit) : Entry
}

private val rowText = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium)

/**
 * A tvOS playback menu (TV_PLAYER_PLAN §7): a list 320 dp wide, opening at the
 * right edge above the bar's buttons, the current choice ticked, small captions
 * over sections. A row with a value opens a further list in place; Back goes up a
 * level, then closes.
 */
@Composable
internal fun TvPopover(title: String, anchorEnd: Dp, entries: () -> List<Entry>, onLevel: (String?) -> Unit = {}, onClose: () -> Unit) {
    val stack = remember { mutableStateListOf<Pair<String, () -> List<Entry>>>() }
    val (heading, list) = stack.lastOrNull() ?: (title to entries)
    val first = remember(stack.size) { FocusRequester() }
    LaunchedEffect(stack.size) { kotlinx.coroutines.delay(40); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) else onClose() }
    LaunchedEffect(stack.size) { onLevel(stack.lastOrNull()?.first) }
    val rows = list()
    val memoryKey = (listOf(title) + stack.map { it.first }).joinToString("›")
    // The row the remote lands on: the one last used in this menu, else the current choice, else the first.
    val landing = PopoverMemory.last[memoryKey]?.let { l -> rows.indexOfFirst { label(it) == l } }?.takeIf { it >= 0 }
        ?: rows.indexOfFirst { it is Entry.Choice && it.on }.takeIf { it >= 0 }
        ?: rows.indexOfFirst { it !is Entry.Caption }
    fun used(e: Entry) { label(e)?.let { PopoverMemory.last[memoryKey] = it } }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomEnd) {
        // The OK release that opened the menu must not choose its first row.
        Column(Modifier.holdsRemote().ignoreHeldOk().padding(end = anchorEnd, bottom = 168.dp).width(320.dp).heightIn(max = 340.dp)
            // Nearly solid, so the picture moving behind never shows through the rows.
            .background(Color(0xFF1F1F23).copy(alpha = 0.96f), RoundedCornerShape(18.dp)).padding(8.dp)) {
            Text(heading, style = rowText.copy(fontSize = 13.sp, color = Palette.textSecondary),
                modifier = Modifier.padding(start = 12.dp, top = 4.dp, bottom = 6.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(rows.size) { i ->
                    val here = if (i == landing) Modifier.focusRequester(first) else Modifier
                    when (val e = rows[i]) {
                        is Entry.Caption -> Text(e.text.uppercase(), style = rowText.copy(fontSize = 11.sp, letterSpacing = 1.sp, color = Palette.textMuted),
                            modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 2.dp))
                        is Entry.Choice -> TvPill({ used(e); e.act(); if (e.closes) onClose() }, here.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                            Box(Modifier.size(20.dp)) { if (e.on) Mark(Symbols.check, size = 16.dp) }
                            Spacer(Modifier.width(8.dp))
                            Text(e.label, style = rowText, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        }
                        is Entry.Link -> TvPill({ used(e); stack.add(e.label to e.open) }, here.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                            Text(e.label, style = rowText, maxLines = 1, modifier = Modifier.weight(1f).alignByBaseline())
                            e.value?.let { Text(it, style = rowText.copy(fontSize = 14.sp), color = pillTint(Palette.textSecondary), maxLines = 1,
                                modifier = Modifier.alignByBaseline()) }
                            Spacer(Modifier.width(6.dp))
                            Mark(Symbols.chevronRight, size = 14.dp, tint = pillTint(Palette.textMuted))
                        }
                        is Entry.Action -> TvPill({ used(e); onClose(); e.act() }, here.fillMaxWidth(), shape = RoundedCornerShape(10.dp)) {
                            Text(e.label, style = rowText, maxLines = 1, modifier = Modifier.weight(1f))
                        }
                        is Entry.Custom -> e.content(here)
                    }
                }
            }
        }
    }
}

/** The row last used in each menu and sub-list, so a menu opens where it was left. */
internal object PopoverMemory { val last = mutableMapOf<String, String>() }

private fun label(e: Entry): String? = when (e) { is Entry.Choice -> e.label; is Entry.Link -> e.label; is Entry.Action -> e.label; else -> null }

/** Every menu keeps to the right edge, on the page margin, whichever button opened it. */
internal val PopoverEnd: Dp = 56.dp

/** Subtitles: off or a track, then the look of them, then finding or fitting them. */
internal fun subtitleEntries(player: ExoPlayer, prefs: Prefs, seriesId: String?, onMore: (() -> Unit)?): List<Entry> {
    val text = trackChoices(player, C.TRACK_TYPE_TEXT)
    fun remember(lang: String) { seriesId?.let { prefs.rememberTracks(it, text = lang) } }
    return buildList {
        add(Entry.Choice("Off", text.none { it.selected }) { choose(player, null, C.TRACK_TYPE_TEXT); remember("off") })
        text.forEach { t -> add(Entry.Choice(t.label.ifEmpty { "Subtitles" }, t.selected) { choose(player, t, C.TRACK_TYPE_TEXT); remember(t.language ?: "off") }) }
        add(Entry.Caption("Style"))
        val sizes = listOf("Small", "Medium", "Large", "Extra Large")
        add(Entry.Link("Size", sizes.getOrNull(prefs.subtitleSize)) {
            sizes.mapIndexed { i, s -> Entry.Choice(s, prefs.subtitleSize == i, closes = false) { prefs.subtitleSize = i } } })
        val looks = listOf("Outline", "Shadow", "Dark Box")
        add(Entry.Link("Look", looks.getOrNull(prefs.subtitleStyle)) {
            looks.mapIndexed { i, s -> Entry.Choice(s, prefs.subtitleStyle == i, closes = false) { prefs.subtitleStyle = i } } })
        onMore?.let { add(Entry.Action("Find or Fix Subtitles…", it)) }
    }
}

/** Audio: the tracks, then the sound settings Apple keeps under them. */
internal fun audioEntries(player: ExoPlayer, prefs: Prefs, seriesId: String?): List<Entry> {
    val audio = trackChoices(player, C.TRACK_TYPE_AUDIO)
    return buildList {
        audio.forEach { a -> add(Entry.Choice(a.label, a.selected) {
            choose(player, a, C.TRACK_TYPE_AUDIO); seriesId?.let { prefs.rememberTracks(it, audio = a.language) } }) }
        add(Entry.Caption("Sound"))
        add(Entry.Choice("Full Dynamic Range", !prefs.nightSound, closes = false) { prefs.nightSound = false })
        add(Entry.Choice("Reduce Loud Sounds", prefs.nightSound, closes = false) { prefs.nightSound = true })
        add(Entry.Link("Enhance Dialogue", if (prefs.dialogueBoost == 0) "Off" else "+${prefs.dialogueBoost} dB") {
            listOf(0, 3, 6, 9).map { v -> Entry.Choice(if (v == 0) "Off" else "+$v dB", prefs.dialogueBoost == v, closes = false) { prefs.dialogueBoost = v } } })
    }
}

/** More: everything else about playback, and the figures for diagnosing it. */
internal fun moreEntries(player: ExoPlayer, prefs: Prefs, speed: () -> Int, setSpeed: (Int) -> Unit, onRemote: (() -> Unit)?): List<Entry> = buildList {
    fun rate(v: Int) = "${v / 100.0}×".replace(".0×", "×")
    add(Entry.Link("Playback Speed", rate(speed())) {
        listOf(75, 100, 125, 150, 200).map { v -> Entry.Choice(rate(v), speed() == v, closes = false) { setSpeed(v) } } })
    // The headset's screen takes the film's own shape, and has no lamp or tone to correct.
    if (!app.lumiere.android.Flavor.quest) add(Entry.Link("Picture", if (prefs.fillsScreen) "Fill" else "Fit") {
        listOf(false to "Fit", true to "Fill").map { (v, l) -> Entry.Choice(l, prefs.fillsScreen == v, closes = false) { prefs.fillsScreen = v } } })
    val tones = listOf("Neutral", "Warmer", "Cooler")
    if (!app.lumiere.android.Flavor.quest) add(Entry.Link("Picture Tone", tones.getOrNull(prefs.pictureTone)) {
        tones.mapIndexed { i, l -> Entry.Choice(l, prefs.pictureTone == i, closes = false) { prefs.pictureTone = i } } })
    if (!app.lumiere.android.Flavor.quest) add(Entry.Link("Lamp", if (prefs.lampBright) "Brightest" else "As Set") {
        listOf(false to "As Set", true to "Brightest").map { (v, l) -> Entry.Choice(l, prefs.lampBright == v, closes = false) { prefs.lampBright = v } } })
    val sleep = when {
        SleepTimer.endOfEpisode -> "End of Episode"
        SleepTimer.until != null -> "${((SleepTimer.until!! - System.currentTimeMillis()) / 60_000L).coerceAtLeast(1)} min"
        else -> "Off"
    }
    add(Entry.Link("Sleep Timer", sleep) {
        listOf(0, -1, 30, 60, 90).map { v ->
            val on = when (v) { 0 -> SleepTimer.until == null && !SleepTimer.endOfEpisode; -1 -> SleepTimer.endOfEpisode; else -> false }
            Entry.Choice(when (v) { 0 -> "Off"; -1 -> "End of Episode"; else -> "$v Minutes" }, on) {
                SleepTimer.endOfEpisode = v == -1
                SleepTimer.until = if (v > 0) System.currentTimeMillis() + v * 60_000L else null
            }
        } })
    onRemote?.let { add(Entry.Action("Phone as Remote…", it)) }
    add(Entry.Caption("Diagnostics"))
    add(Entry.Link("Playback Info", null) { listOf(Entry.Custom { m -> PlaybackInfo(player, m) }) })
}
