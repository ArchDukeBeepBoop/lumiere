package app.lumiere.android.remote

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.Palette

/**
 * The phone as the TV's remote: which TV, the pairing code the first time,
 * what is playing with a seek bar and its tracks, the arrows and OK, Back,
 * Home and Menu, the volume, and a keyboard for the TV's search.
 */
@Composable
fun RemoteScreen(state: AppState) {
    val context = LocalContext.current
    DisposableEffect(Unit) {
        RemoteClient.discover(context)
        onDispose { RemoteClient.stopDiscovery(context) }
    }
    Column(Modifier.fillMaxSize().background(Palette.canvas).verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Remote", style = app.lumiere.android.ui.IosType.largeTitle, color = Palette.textPrimary)
        TvPicker()
        when (RemoteClient.status) {
            RemoteClient.Status.NeedsCode -> CodeEntry()
            RemoteClient.Status.Connected -> {
                NowPlaying(state)
                if (state.settings.remoteTouchpad) Touchpad() else Pad()
                Keyboard()
            }
            RemoteClient.Status.Connecting -> Text("Connecting to ${RemoteClient.tv?.name}…", style = MaterialTheme.typography.bodyMedium)
            RemoteClient.Status.Failed -> {
                Text(RemoteClient.problem ?: "The connection was lost.", style = MaterialTheme.typography.bodyMedium)
                RemoteClient.tv?.let { tv -> LButton(onClick = { RemoteClient.connect(context, tv) }) { Text("Try again") } }
            }
            RemoteClient.Status.Idle -> if (RemoteClient.found.isNotEmpty())
                Text("Choose a TV above to connect.", style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary)
        }
    }
}

@Composable
private fun TvPicker() {
    val context = LocalContext.current
    if (RemoteClient.found.isEmpty()) {
        Text("Looking for Lumiere on a TV on this Wi-Fi… Open Lumiere on the TV if it is not.",
            style = MaterialTheme.typography.bodyMedium)
        return
    }
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(RemoteClient.found, key = { it.name }) { tv ->
            LChip(selected = RemoteClient.tv?.name == tv.name && RemoteClient.status != RemoteClient.Status.Idle,
                onClick = { RemoteClient.connect(context, tv) }, label = { Text(tv.name) })
        }
    }
}

@Composable
private fun CodeEntry() {
    val context = LocalContext.current
    var code by remember { mutableStateOf("") }
    Text("Enter the code ${RemoteClient.tv?.name ?: "the TV"} shows. This phone is remembered after that.",
        style = MaterialTheme.typography.bodyMedium)
    RemoteClient.problem?.let { Text(it, color = Palette.accent, style = MaterialTheme.typography.labelMedium) }
    OutlinedTextField(code, { v -> code = v.filter(Char::isDigit).take(4); if (code.length == 4) RemoteClient.pair(context, code) },
        label = { Text("Code") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
}

@Composable
private fun NowPlaying(state: AppState) {
    val tv = RemoteClient.state
    if (tv.itemId == null) return
    // Something from the private room is named only while this phone's room is open.
    val hidden = tv.isPrivate && !state.roomOpen
    Column(Modifier.fillMaxWidth().background(Palette.surface, MaterialTheme.shapes.medium).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(if (hidden) "Playing on ${RemoteClient.tv?.name}" else tv.title, style = MaterialTheme.typography.titleMedium,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (!hidden && tv.subtitle.isNotEmpty()) Text(tv.subtitle, style = MaterialTheme.typography.labelMedium, maxLines = 1)
        var dragging by remember { mutableStateOf<Float?>(null) }
        if (tv.duration > 0) {
            Slider(value = dragging ?: (tv.position / tv.duration).toFloat().coerceIn(0f, 1f),
                onValueChange = { dragging = it },
                onValueChangeFinished = { dragging?.let { RemoteClient.send(Remote.seek(it * tv.duration)) }; dragging = null },
                colors = SliderDefaults.colors(thumbColor = Palette.accent, activeTrackColor = Palette.accent))
            Text("${clock(dragging?.let { it * tv.duration } ?: tv.position)} / ${clock(tv.duration)}", style = MaterialTheme.typography.labelMedium)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
            Big(Icons.Default.Replay10, "Back ten seconds") { RemoteClient.send(Remote.skip(-10)) }
            Big(if (tv.playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (tv.playing) "Pause" else "Play") {
                RemoteClient.send(Remote.key("playpause"))
            }
            Big(Icons.Default.Forward10, "Forward ten seconds") { RemoteClient.send(Remote.skip(10)) }
        }
        if (!hidden) {
            Tracks("Audio", tv.audio) { RemoteClient.send(Remote.audio(it)) }
            Tracks("Subtitles", listOf(TvTrack(-1, "Off", tv.subtitles.none { it.selected })) + tv.subtitles) {
                RemoteClient.send(Remote.subtitle(it))
            }
        }
    }
}

@Composable
private fun Tracks(title: String, tracks: List<TvTrack>, onPick: (Int) -> Unit) {
    if (tracks.size < 2) return
    Text(title, style = MaterialTheme.typography.labelMedium)
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(tracks, key = { it.index }) { t -> LChip(t.selected, { onPick(t.index) }, { Text(t.label, maxLines = 1) }) }
    }
}

/** The arrows around OK, then Back, Home and Menu, then the volume. */
@Composable
private fun Pad() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Key(Icons.Default.KeyboardArrowUp, "Up", "up")
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Key(Icons.Default.KeyboardArrowLeft, "Left", "left")
            val haptic = LocalHapticFeedback.current
            Box(Modifier.size(96.dp).background(Palette.accent, CircleShape), contentAlignment = Alignment.Center) {
                LTextButton(onClick = { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); RemoteClient.send(Remote.key("ok")) },
                    modifier = Modifier.size(96.dp)) { Text("OK", color = Palette.onAccent, style = MaterialTheme.typography.titleLarge) }
            }
            Key(Icons.Default.KeyboardArrowRight, "Right", "right")
        }
        Key(Icons.Default.KeyboardArrowDown, "Down", "down")
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            Key(Icons.AutoMirrored.Filled.ArrowBack, "Back", "back")
            Key(Icons.Default.Home, "Home", "home")
            Key(Icons.Default.Menu, "Menu", "menu")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            Key(Icons.Default.Remove, "Volume down", "voldown")
            Key(Icons.AutoMirrored.Filled.VolumeOff, "Mute", "mute")
            Key(Icons.Default.Add, "Volume up", "volup")
        }
    }
}

@Composable
private fun Key(icon: ImageVector, label: String, key: String) {
    val haptic = LocalHapticFeedback.current
    LIconButton(onClick = { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); RemoteClient.send(Remote.key(key)) },
        modifier = Modifier.size(64.dp).background(Palette.surface, CircleShape)) {
        Icon(icon, label, tint = Palette.textPrimary, modifier = Modifier.size(32.dp))
    }
}

@Composable
private fun Big(icon: ImageVector, label: String, onClick: () -> Unit) {
    LIconButton(onClick = onClick, modifier = Modifier.size(56.dp)) {
        Icon(icon, label, tint = Palette.textPrimary, modifier = Modifier.size(36.dp))
    }
}

/**
 * Apple's iPhone remote: a large dark surface you swipe across — each step
 * of a swipe moves once, with a tick — and tap to choose; a soft light under
 * the finger. Then Back, Home, Play/Pause and Menu, and the volume.
 */
@Composable
private fun Touchpad() {
    val haptic = LocalHapticFeedback.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    val step = with(density) { 56.dp.toPx() }
    var touch by remember { mutableStateOf<androidx.compose.ui.geometry.Offset?>(null) }
    val glow by androidx.compose.animation.core.animateFloatAsState(if (touch != null) 1f else 0f, label = "glow")
    var last by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    if (touch != null) last = touch!!
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(androidx.compose.foundation.shape.RoundedCornerShape(28.dp))
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(androidx.compose.ui.graphics.Color(0xFF2A2A2D),
                androidx.compose.ui.graphics.Color(0xFF1C1C1E))))
            .drawBehind {
                if (glow > 0f) drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(
                    listOf(androidx.compose.ui.graphics.Color.White.copy(alpha = 0.16f * glow), androidx.compose.ui.graphics.Color.Transparent),
                    center = last, radius = size.minDimension * 0.35f), radius = size.minDimension * 0.35f, center = last)
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    touch = down.position
                    val started = System.currentTimeMillis()
                    var acc = androidx.compose.ui.geometry.Offset.Zero
                    var moved = false
                    while (true) {
                        val e = awaitPointerEvent()
                        val c = e.changes.firstOrNull { it.id == down.id } ?: break
                        if (!c.pressed) break
                        acc += c.position - c.previousPosition
                        touch = c.position
                        c.consume()
                        // One step per stretch of swipe, along whichever way it mostly went.
                        while (kotlin.math.abs(acc.x) >= step || kotlin.math.abs(acc.y) >= step) {
                            moved = true
                            val key = if (kotlin.math.abs(acc.x) >= kotlin.math.abs(acc.y)) {
                                val k = if (acc.x > 0) "right" else "left"; acc = acc.copy(x = acc.x - step * kotlin.math.sign(acc.x)); k
                            } else {
                                val k = if (acc.y > 0) "down" else "up"; acc = acc.copy(y = acc.y - step * kotlin.math.sign(acc.y)); k
                            }
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            RemoteClient.send(Remote.key(key))
                        }
                    }
                    if (!moved && System.currentTimeMillis() - started < 450) {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        RemoteClient.send(Remote.key("ok"))
                    }
                    touch = null
                }
            }, contentAlignment = Alignment.Center) {
            Text("Swipe to move · Tap to select", style = MaterialTheme.typography.labelMedium,
                color = Palette.textMuted.copy(alpha = 1f - glow))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
            Key(Icons.AutoMirrored.Filled.ArrowBack, "Back", "back")
            Key(Icons.Default.Home, "Home", "home")
            Key(Icons.Default.PlayArrow, "Play or pause", "playpause")
            Key(Icons.Default.Menu, "Menu", "menu")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            Key(Icons.Default.Remove, "Volume down", "voldown")
            Key(Icons.AutoMirrored.Filled.VolumeOff, "Mute", "mute")
            Key(Icons.Default.Add, "Volume up", "volup")
        }
    }
}

/** Typing on the phone fills the TV's focused search field as you go. */
@Composable
private fun Keyboard() {
    var text by remember { mutableStateOf("") }
    OutlinedTextField(text, { text = it; RemoteClient.send(Remote.text(it)) },
        label = { Text(if (RemoteClient.state.typing) "Type on the TV" else "Type into the TV's search") },
        singleLine = true, modifier = Modifier.fillMaxWidth())
}

private fun clock(seconds: Double): String {
    val s = seconds.toLong().coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}
