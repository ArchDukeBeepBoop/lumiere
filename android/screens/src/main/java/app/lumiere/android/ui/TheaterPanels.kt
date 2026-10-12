package app.lumiere.android.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.key
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.PushPin as PushPinOutline
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Brightness6
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.AirlineSeatReclineNormal
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.media3.common.C
import app.lumiere.android.player.choose
import app.lumiere.android.player.trackChoices
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
import kotlinx.coroutines.launch

/**
 * The Theater's transport: a bar of glass that floats near your hands while
 * a film plays on its own screen — back and forward ten seconds, play and
 * pause, a scrubber with the film's frames floating above it as you drag,
 * then the shortcuts you've pinned (the screen's size, curve and place,
 * audio and subtitles, speed, the sleep timer…) and More, which holds every
 * one of them, to use or pin. It shows when the film is paused or you've just touched anything, and
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
        // Audio and subtitles, or More: one sheet at a time over the bar.
        var sheet by remember(c) { mutableStateOf(Sheet.NONE) }
        var speed by remember(c) { mutableFloatStateOf(c.player.playbackParameters.speed) }
        LaunchedEffect(c) {
            while (true) {
                position = c.clock.now(); duration = c.clock.duration(); playing = c.player.isPlaying
                speed = c.player.playbackParameters.speed
                delay(250)
            }
        }
        // Open, a sheet keeps the bar up.
        LaunchedEffect(sheet) { while (sheet != Sheet.NONE) { Theater.poke(); delay(1000) } }
        fun touch(action: () -> Unit) { Theater.poke(); action() }
        fun look(a: Shortcuts.Action) = lookOf(a, speed, tracksOpen = sheet == Sheet.TRACKS)
        fun perform(a: Shortcuts.Action) {
            Theater.poke()
            when (a) {
                Shortcuts.Action.TRACKS -> sheet = if (sheet == Sheet.TRACKS) Sheet.NONE else Sheet.TRACKS
                Shortcuts.Action.SMALLER -> { Stage.smaller(); if (Stage.place == Stage.Place.CINEMA) Theater.say("Your seat: ${Stage.seatName().lowercase()}") }
                Shortcuts.Action.LARGER -> { Stage.larger(); if (Stage.place == Stage.Place.CINEMA) Theater.say("Your seat: ${Stage.seatName().lowercase()}") }
                Shortcuts.Action.CURVE -> if (Stage.place == Stage.Place.CINEMA) Theater.say("The cinema's screen is its hall's own, flat")
                    else Stage.toggleCurve()
                Shortcuts.Action.PLACE -> Stage.nextPlace()
                Shortcuts.Action.PLAYER_MENU -> Theater.windowAsked = !Theater.windowAsked
                Shortcuts.Action.SLEEP -> Stage.cycleSleep()
                Shortcuts.Action.BRING_HERE -> Stage.bringHere()
                Shortcuts.Action.SOUNDS -> Stage.toggleAmbience()
                Shortcuts.Action.PICTURE -> sheet = if (sheet == Sheet.PICTURE) Sheet.NONE else Sheet.PICTURE
                Shortcuts.Action.POSTURE -> Stage.toggleFollowPosture()
                Shortcuts.Action.HAND_MENU -> Stage.toggleHandMenu()
                Shortcuts.Action.WALL -> if (Stage.place == Stage.Place.ROOM) Stage.askMount()
                    else Theater.say("The screen goes on a wall in your room: choose your room first")
                // The player may have just been let go as the film ended; the speed then simply stays.
                Shortcuts.Action.SPEED -> runCatching {
                    c.player.setPlaybackSpeed(Shortcuts.nextSpeed(c.player.playbackParameters.speed))
                    speed = c.player.playbackParameters.speed
                }
            }
        }
        // The panel is tall and clear above the bar, so audio and subtitles, or More, open over it.
        // A word for a few seconds, over everything else.
        val notice = Theater.notice
        LaunchedEffect(notice) { if (notice != null) { delay(5000); Theater.notice = null } }
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.Bottom)) {
            if (notice != null) Text(notice, style = MaterialTheme.typography.titleMedium, color = Palette.textPrimary,
                modifier = Modifier.align(Alignment.CenterHorizontally).spatialGlass(28).padding(horizontal = 22.dp, vertical = 12.dp))
            when (sheet) {
                Sheet.TRACKS -> TrackSheet(c) { sheet = Sheet.NONE }
                Sheet.MORE -> MoreSheet(::look, ::perform) { sheet = Sheet.NONE }
                Sheet.PICTURE -> PictureSheet(c) { sheet = Sheet.NONE }
                Sheet.NONE -> Unit
            }
            Column(Modifier.fillMaxWidth().height(250.dp).spatialGlass(30).padding(horizontal = 24.dp, vertical = 14.dp),
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
                    GlassButton(Icons.Default.Replay10, "Back 10 seconds", size = 52.dp) { touch { c.clock.seek((c.clock.now() - 10).coerceAtLeast(0.0)) } }
                    GlassButton(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play",
                        chosen = true, size = 60.dp) { touch { if (c.player.isPlaying) c.player.pause() else c.player.play() } }
                    GlassButton(Icons.Default.Forward10, "Forward 10 seconds", size = 52.dp) { touch { c.clock.seek(c.clock.now() + 10) } }
                    Theater.next?.let { next -> GlassButton(Icons.Default.SkipNext, "Next episode", size = 52.dp) { touch(next) } }
                    Spacer(Modifier.weight(1f))
                    // Your pins, at most six: with the four above, More and Close it is 12 buttons in the bar's 1052 dp.
                    Shortcuts.pinned.forEach { a ->
                        key(a) { val l = look(a); GlassButton(l.icon, l.label, chosen = l.chosen, caption = l.caption, size = 52.dp) { perform(a) } }
                    }
                    GlassButton(Icons.Default.MoreHoriz, "More", chosen = sheet == Sheet.MORE, size = 52.dp) {
                        touch { sheet = if (sheet == Sheet.MORE) Sheet.NONE else Sheet.MORE }
                    }
                    GlassButton(Icons.Default.Close, "Stop watching", size = 52.dp) { touch { c.exit() } }
                }
            }
        }
    }
}

/** What opens over the bar: never two at once. */
private enum class Sheet { NONE, TRACKS, MORE, PICTURE }

/** How a shortcut shows: its icon and name, a [caption] under the icon on the bar, a [value] beside its name under More. */
private class Look(val icon: ImageVector, val label: String, val caption: String? = null, val value: String? = null, val chosen: Boolean = false)

private fun lookOf(a: Shortcuts.Action, speed: Float, tracksOpen: Boolean): Look = when (a) {
    Shortcuts.Action.TRACKS -> Look(Icons.Default.Subtitles, "Audio & Subtitles", chosen = tracksOpen)
    // In the cinema the screen is a wall of a set size, and a size is the row you sit in.
    Shortcuts.Action.SMALLER -> if (Stage.place == Stage.Place.CINEMA) Look(Icons.Default.ZoomOut, "Sit further back", value = Stage.seatName())
        else Look(Icons.Default.ZoomOut, "Smaller screen")
    Shortcuts.Action.LARGER -> if (Stage.place == Stage.Place.CINEMA) Look(Icons.Default.ZoomIn, "Sit nearer the screen", value = Stage.seatName())
        else Look(Icons.Default.ZoomIn, "Larger screen")
    Shortcuts.Action.CURVE -> if (Stage.place == Stage.Place.CINEMA) Look(Icons.Default.Crop169, "Curve the screen", value = "Flat in the cinema")
        else if (Stage.curved) Look(Icons.Default.Crop169, "Flatten the screen", value = "Curved now")
        else Look(Icons.Default.Panorama, "Curve the screen", value = "Flat now")
    Shortcuts.Action.PLACE -> placeCaption(Stage.place).let { Look(placeIcon(Stage.place), "Watch in ${Stage.place.label}", caption = it, value = "$it: tap for the next") }
    Shortcuts.Action.PLAYER_MENU -> Look(Icons.Default.Tune, "Player menu", value = "Speed, picture, sound", chosen = Theater.windowAsked)
    Shortcuts.Action.SLEEP -> Stage.sleepMinutes.let { m ->
        Look(Icons.Default.Bedtime, if (m == 0) "Sleep timer" else "Sleep in $m minutes", caption = m.takeIf { it > 0 }?.toString(),
            value = if (m == 0) "Off" else null, chosen = m > 0)
    }
    Shortcuts.Action.BRING_HERE -> Look(Icons.Default.CenterFocusStrong, "Bring everything here")
    Shortcuts.Action.SPEED -> Shortcuts.speedLabel(speed).let { Look(Icons.Default.Speed, "Playback speed", caption = it, value = it, chosen = it != "1×") }
    Shortcuts.Action.WALL -> when {
        Stage.mount != null -> Look(Icons.Default.Tv, "Take the screen off the wall", value = "On your wall now", chosen = true)
        Stage.place != Stage.Place.ROOM -> Look(Icons.Default.Tv, "Screen on your wall", value = "In your room")
        else -> Look(Icons.Default.Tv, "Screen on the wall before you", value = "Look at a wall, then tap")
    }
    Shortcuts.Action.SOUNDS -> if (Stage.ambience) Look(Icons.Default.GraphicEq, "Sounds of the place", value = "On: heard while paused", chosen = true)
        else Look(Icons.Default.GraphicEq, "Sounds of the place", value = "Off")
    Shortcuts.Action.PICTURE -> Look(Icons.Default.Brightness6, "Picture", value = "Brightness, contrast, wide films")
    Shortcuts.Action.HAND_MENU -> if (Stage.handMenu) Look(Icons.Default.PanTool, "Hand menu", value = "Raise a hand and look at it", chosen = true)
        else Look(Icons.Default.PanTool, "Hand menu", value = "Off")
    Shortcuts.Action.POSTURE -> if (Stage.followPosture) Look(Icons.Default.AirlineSeatReclineNormal, "Follow when you sit or stand", value = "On", chosen = true)
        else Look(Icons.Default.AirlineSeatReclineNormal, "Follow when you sit or stand", value = "Off")
}

/**
 * More, in the same clear space as audio and subtitles: every shortcut in
 * three columns, each a row you tap to use, with a pin at its end to keep it
 * on the bar or take it off. Six fit on the bar; a seventh says so.
 */
@Composable
private fun MoreSheet(look: (Shortcuts.Action) -> Look, perform: (Shortcuts.Action) -> Unit, onClose: () -> Unit) {
    var full by remember { mutableStateOf(false) }
    LaunchedEffect(full) { if (full) { delay(4000); full = false } }
    Row(Modifier.fillMaxWidth().heightIn(max = 290.dp).spatialGlass(30).padding(20.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (full) "The bar holds ${Shortcuts.MAX_PINNED} shortcuts: unpin one to make room" else "Tap to use · pin to keep it on the bar",
                style = MaterialTheme.typography.titleSmall, color = if (full) Palette.accent else Palette.textSecondary, maxLines = 1)
            Shortcuts.Action.entries.chunked(3).forEach { line ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    line.forEach { a ->
                        MoreRow(look(a), pinned = a in Shortcuts.pinned, Modifier.weight(1f), onUse = { perform(a) }) {
                            Theater.poke(); full = !Shortcuts.toggle(a)
                        }
                    }
                }
            }
        }
        GlassButton(Icons.Default.Close, "Close", size = 52.dp, onClick = onClose)
    }
}

@Composable
private fun MoreRow(look: Look, pinned: Boolean, modifier: Modifier, onUse: () -> Unit, onPin: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    Row(modifier.heightIn(min = 52.dp)
        .background(if (hovered) Color.White.copy(alpha = 0.12f) else Color.Transparent, RoundedCornerShape(12.dp))
        .hoverable(source).clickable(interactionSource = source, indication = null, onClick = onUse)
        .padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(look.icon, null, tint = if (look.chosen) Palette.accent else Palette.textPrimary, modifier = Modifier.size(24.dp))
        Column(Modifier.weight(1f)) {
            Text(look.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            look.value?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        // Filled when it's on the bar, an outline when it isn't.
        GlassButton(if (pinned) Icons.Default.PushPin else Icons.Outlined.PushPinOutline,
            if (pinned) "Unpin ${look.label} from the bar" else "Pin ${look.label} to the bar", size = 52.dp, onClick = onPin)
    }
}

/**
 * Audio and subtitles, as Netflix lays them out: two columns, the chosen
 * one ticked, subtitles with Off first. A choice applies at once.
 */
@Composable
private fun TrackSheet(c: Theater.Controls, onClose: () -> Unit) {
    var tick by remember { mutableIntStateOf(0) }
    val audio = remember(tick) { trackChoices(c.player, C.TRACK_TYPE_AUDIO) }
    val text = remember(tick) { trackChoices(c.player, C.TRACK_TYPE_TEXT) }
    val textOff = text.none { it.selected }
    val prefs = app.lumiere.android.OpenApp.state?.settings
    // A second language under the first: the film's other text subtitles, read from the server.
    val readable = remember(c) { c.streams.filter { app.lumiere.android.player.SecondSubtitles.readable(it.codec) } }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Row(Modifier.fillMaxWidth().heightIn(max = 290.dp).spatialGlass(30).padding(20.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
        TrackColumn("Audio", Modifier.weight(1f), audio.map { it.label to it.selected }) { i ->
            choose(c.player, audio[i], C.TRACK_TYPE_AUDIO); tick++
        }
        TrackColumn("Subtitles", Modifier.weight(1f), listOf("Off" to textOff) + text.map { it.label to it.selected }) { i ->
            choose(c.player, if (i == 0) null else text[i - 1], C.TRACK_TYPE_TEXT); tick++
        }
        val second = Theater.second
        TrackColumn("And under them", Modifier.weight(1f), listOf("Nothing" to (second == null)) +
            readable.map { app.lumiere.android.player.SecondSubtitles.label(it.language, it.title) to (second?.index == it.index) }) { i ->
            if (i == 0) Theater.second = null
            else readable[i - 1].let { st ->
                val label = app.lumiere.android.player.SecondSubtitles.label(st.language, st.title)
                scope.launch {
                    val cues = runCatching { app.lumiere.android.player.SecondSubtitles.parse(c.server.subtitleText(c.itemId, c.mediaSourceId, st.index)) }
                        .getOrDefault(emptyList())
                    if (cues.isEmpty()) Theater.say("$label can't be shown under the subtitles")
                    else Theater.second = app.lumiere.android.player.SecondSubtitles.Track(st.index, label, cues)
                }
            }
        }
        // The captions themselves: their size (the same setting as the window's), and where they are.
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Captions", style = MaterialTheme.typography.titleSmall, color = Palette.textSecondary)
            if (prefs != null) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf("S", "M", "L", "XL").forEachIndexed { i, s ->
                    GlassButton(Icons.Default.Subtitles, "Caption size $s", chosen = prefs.subtitleSize == i, caption = s, size = 44.dp) {
                        Theater.poke(); prefs.subtitleSize = i
                    }
                }
            }
            TrackColumn("", Modifier, listOf("On the screen" to !Stage.captionsNear, "Before you" to Stage.captionsNear)) { i ->
                if ((i == 1) != Stage.captionsNear) Stage.toggleCaptionsNear()
            }
        }
        GlassButton(Icons.Default.Close, "Close", size = 52.dp, onClick = onClose)
    }
}

/**
 * The film's own picture: brightness and contrast in a few steps either
 * side of as it came, kept for the film (or the whole show), and wide films
 * on a screen as tall as a 16:9 one, so they're wider rather than shorter.
 */
@Composable
private fun PictureSheet(c: Theater.Controls, onClose: () -> Unit) {
    var p by remember(c, Stage.pictureChanges) { mutableStateOf(Stage.pictureFor(c.pictureKey)) }
    fun set(next: Stage.Picture) { Theater.poke(); p = next; Stage.setPicture(c.pictureKey, next) }
    val adjustable = Theater.pictureAdjustable != false
    Row(Modifier.fillMaxWidth().spatialGlass(30).padding(20.dp), horizontalArrangement = Arrangement.spacedBy(22.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (adjustable) {
            Stepper("Brightness", p.brightness) { set(p.copy(brightness = it)) }
            Stepper("Contrast", p.contrast) { set(p.copy(contrast = it)) }
            if (!p.plain) TextButtonGlass("As it came") { set(Stage.Picture()) }
        } else Text("This film is HDR: it's shown as it came", color = Palette.textSecondary, modifier = Modifier.weight(1f))
        Spacer(Modifier.weight(1f))
        // In the cinema a wide film is as wide as its screen, as a cinema's masking has it.
        if (Stage.place != Stage.Place.CINEMA) Column {
            Text("Wide films", style = MaterialTheme.typography.titleSmall, color = Palette.textSecondary)
            TrackColumn("", Modifier, listOf("The same width" to !Stage.scopeFill, "Wider, as in a scope cinema" to Stage.scopeFill)) { i ->
                if ((i == 1) != Stage.scopeFill) Stage.toggleScopeFill()
            }
        }
        GlassButton(Icons.Default.Close, "Close", size = 52.dp, onClick = onClose)
    }
}

@Composable
private fun Stepper(name: String, value: Int, set: (Int) -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(name, style = MaterialTheme.typography.titleSmall, color = Palette.textSecondary)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GlassButton(Icons.Default.Remove, "Less $name", size = 48.dp) { set((value - 1).coerceAtLeast(-Stage.PICTURE_STEPS)) }
            Text(if (value > 0) "+$value" else "$value", style = MaterialTheme.typography.titleMedium, modifier = Modifier.width(36.dp),
                textAlign = TextAlign.Center)
            GlassButton(Icons.Default.Add, "More $name", size = 48.dp) { set((value + 1).coerceAtMost(Stage.PICTURE_STEPS)) }
        }
    }
}

@Composable
private fun TextButtonGlass(label: String, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    Text(label, style = MaterialTheme.typography.titleSmall, color = Palette.textPrimary,
        modifier = Modifier.background(if (hovered) Color.White.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.08f), RoundedCornerShape(50))
            .hoverable(source).clickable(interactionSource = source, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp))
}

@Composable
private fun TrackColumn(title: String, modifier: Modifier, rows: List<Pair<String, Boolean>>, onPick: (Int) -> Unit) {
    Column(modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (title.isNotEmpty()) Text(title, style = MaterialTheme.typography.titleSmall, color = Palette.textSecondary)
        if (title.isNotEmpty() && rows.isEmpty()) Text("None in this file", color = Palette.textSecondary)
        rows.forEachIndexed { i, (label, chosen) ->
            val source = remember { MutableInteractionSource() }
            val hovered by source.collectIsHoveredAsState()
            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp)
                .background(if (hovered) Color.White.copy(alpha = 0.12f) else Color.Transparent, RoundedCornerShape(12.dp))
                .hoverable(source).clickable(interactionSource = source, indication = null) { Theater.poke(); onPick(i) }
                .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (chosen) "✓" else "", modifier = Modifier.width(28.dp), color = Palette.accent)
                Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
        // The second language's line now, from the film's clock.
        val second = Theater.second
        var under by remember { mutableStateOf<String?>(null) }
        LaunchedEffect(second) {
            under = null
            val track = second ?: return@LaunchedEffect
            while (true) {
                under = Theater.controls?.clock?.now()?.let { app.lumiere.android.player.SecondSubtitles.at(track.cues, (it * 1000).toLong()) }
                delay(120)
            }
        }
        if (cues.isEmpty() && under == null) return@LumiereTheme
        // The same four sizes as the window's subtitles.
        val size = listOf(36, 46, 56, 66)[(app.lumiere.android.OpenApp.state?.settings?.subtitleSize ?: 1).coerceIn(0, 3)]
        Box(Modifier.fillMaxSize().padding(bottom = 24.dp), contentAlignment = Alignment.BottomCenter) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                cues.forEach { cue ->
                    val bitmap = cue.bitmap
                    val text = cue.text?.toString()?.trim()
                    when {
                        bitmap != null -> Image(bitmap.asImageBitmap(), null,
                            Modifier.fillMaxWidth(if (cue.size > 0f && cue.size <= 1f) cue.size else 0.6f))
                        !text.isNullOrEmpty() -> Text(text, textAlign = TextAlign.Center,
                            style = TextStyle(fontSize = size.sp, color = Color.White, lineHeight = (size * 1.18f).sp,
                                shadow = Shadow(Color.Black, blurRadius = 6f)),
                            modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 18.dp, vertical = 6.dp))
                    }
                }
                // The second language: a little smaller, warm, under the first.
                under?.let {
                    Text(it, textAlign = TextAlign.Center,
                        style = TextStyle(fontSize = (size * 0.82f).sp, color = Color(0xFFFFE7A8), lineHeight = (size * 0.98f).sp,
                            shadow = Shadow(Color.Black, blurRadius = 6f)),
                        modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                            .padding(horizontal = 16.dp, vertical = 4.dp))
                }
            }
        }
    }
}
