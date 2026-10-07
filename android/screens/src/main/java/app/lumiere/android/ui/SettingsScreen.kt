package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue

/** Every preference in one place, grouped as on the Mac. */
@Composable
fun SettingsScreen(state: AppState) {
    val form = LocalFormFactor.current
    val p = state.settings
    val session = state.session
    val tv = LocalFormFactor.current.isTv
    LazyColumn(
        Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { Text("Settings", style = MaterialTheme.typography.headlineLarge) }
        item { YourSetupSection(state) }

        item { Section("Playback") }
        item { Toggle("Play the next episode automatically", p.playsNext) { p.playsNext = it } }
        if (!tv) item {
            Toggle("Keep a video's sound playing with the screen off", p.videoInBackground) { p.videoInBackground = it }
        }
        if (p.playsNext) item {
            Text("Ask \u201CStill watching?\u201D", style = MaterialTheme.typography.titleMedium)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(listOf(0, 2, 3, 4, 5, 8)) { n ->
                    LChip(p.stillWatchingAfter == n, { p.stillWatchingAfter = n },
                        { Text(if (n == 0) "Never" else "After $n") })
                }
            }
        }
        item { Toggle("Skip intros without asking", p.skipsIntros) { p.skipsIntros = it } }
        item { Toggle("Subtitles on", p.subtitlesOn) { p.subtitlesOn = it } }
        item {
            Toggle("Anime in Japanese with English subtitles", p.animeJapanese, "In any library named Anime.") {
                p.animeJapanese = it
            }
        }

        item { Section("Subtitles & Sound") }
        item {
            Toggle("Burn anime subtitles into the picture", p.burnsInSubtitles,
                "Styled subtitles are always drawn with their fonts and colours. Burned in looks identical to hardcoded " +
                    "subtitles but works the device harder; off draws them over the picture. Applies from the next film.") {
                p.burnsInSubtitles = it
            }
        }
        item {
            // Two fingers drag them during a video on a phone; this sets the same place.
            val heights = listOf(0.02f, 0.06f, 0.12f, 0.2f)
            Choice("Subtitle height", listOf("Lowest", "Normal", "Higher", "Highest"),
                heights.indices.minBy { kotlin.math.abs(heights[it] - p.subtitleLift) }) { p.subtitleLift = heights[it] }
        }
        item { Choice("Plain subtitle size", listOf("Small", "Medium", "Large", "Extra large"), p.subtitleSize) { p.subtitleSize = it } }
        item { Choice("Plain subtitle look", listOf("Outline", "Shadow", "Dark box"), p.subtitleStyle) { p.subtitleStyle = it } }
        item { Choice("Dialogue boost", listOf("Off", "+3 dB", "+6 dB", "+9 dB"), p.dialogueBoost / 3) { p.dialogueBoost = it * 3 } }
        item { Toggle("Night sound", p.nightSound, "Loud scenes quieter and quiet ones louder.") { p.nightSound = it } }

        item { Section("TV & Projector") }
        item { Toggle("Skip Intro counts down and skips by itself", p.skipCountdown) { p.skipCountdown = it } }
        item {
            Choice("Screensaver after", listOf("Never", "2 min", "5 min", "10 min", "30 min"),
                listOf(0, 2, 5, 10, 30).indexOf(p.screensaverMinutes).coerceAtLeast(0)) {
                p.screensaverMinutes = listOf(0, 2, 5, 10, 30)[it]
            }
        }
        item { Toggle("Darker menus from 10 pm to 6 am", p.dimsAtNight) { p.dimsAtNight = it } }
        item { DevicePin(state) }
        item { LButton(primary = false, onClick = { p.tvTourShown = false; state.tab(app.lumiere.android.Screen.Home) }) { Text("Show the Remote Tour Again") } }
        item { Text("TV Home rows", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)) }
        val order = p.tvRowOrder
        items(order.size) { i ->
            val key = order[i]
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LChip(key !in p.tvRowsHidden, { p.tvRowsHidden = if (key in p.tvRowsHidden) p.tvRowsHidden - key else p.tvRowsHidden + key },
                    { Text(app.lumiere.android.Prefs.TV_ROW_NAMES[key] ?: key) })
                LButton(primary = false, enabled = i > 0, onClick = { p.tvRowOrder = order.toMutableList().apply { add(i - 1, removeAt(i)) } }) { Text("↑") }
                LButton(primary = false, enabled = i < order.lastIndex, onClick = { p.tvRowOrder = order.toMutableList().apply { add(i + 1, removeAt(i)) } }) { Text("↓") }
            }
        }

        item { Section("Private Room") }
        item {
            Note("Private libraries stay off Home, search, Continue Watching and Downloads until you open the room " +
                "with the lock on Home. It keeps them off a screen other people can see; it is not encryption.")
        }
        item {
            Toggle("Same private libraries as the Mac", p.privateFollowsMac,
                "Set in Lumiere's Settings on the Mac, under Privacy.") { p.privateFollowsMac = it }
        }
        if (p.privateFollowsMac) item {
            val names = state.views.filter { it.id in state.macPrivate }.joinToString(", ") { it.name }
            Note(if (names.isEmpty()) "The Mac has no private libraries." else "Private: $names")
        } else {
            items(state.views.filter { it.collectionType != "boxsets" && it.collectionType != "playlists" },
                key = { it.id }) { v ->
                Row(Modifier.fillMaxWidth().focusCard { p.privateLibraries = p.privateLibraries.toggle(v.id) },
                    verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(v.id in p.privateLibraries, { p.privateLibraries = p.privateLibraries.toggle(v.id) })
                    Text(v.name, style = MaterialTheme.typography.titleMedium)
                }
            }
            if (state.views.isEmpty()) item { Note("Open Home once to list the libraries.") }
        }
        item { Toggle("Ask for the phone's lock to open it", p.roomRequiresUnlock) { p.roomRequiresUnlock = it } }
        item {
            Text("Shut the room after leaving the app", style = MaterialTheme.typography.titleMedium)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(listOf(0, 1, 5, 15, 60, -1)) { m ->
                    LChip(p.roomLockMinutes == m, { p.roomLockMinutes = m }, {
                        Text(when (m) { 0 -> "At once"; -1 -> "Never"; 60 -> "1 hour"; else -> "$m min" })
                    })
                }
            }
        }
        item {
            Toggle("Grey palette inside", p.roomUsesOwnTheme, "So it is plain which space is open.") {
                p.roomUsesOwnTheme = it
                if (state.roomOpen) RoomTheme.isOn = it
            }
        }
        item {
            Toggle("Blur covers in lists", p.roomBlursCovers, "Clear on a title's own page.") {
                p.roomBlursCovers = it
                if (state.roomOpen) RoomTheme.blursCovers = it
            }
        }
        item {
            Toggle("Block screenshots inside", p.roomBlocksCapture,
                "No screenshots, screen recording or app-switcher preview while the room is open.") {
                p.roomBlocksCapture = it
            }
        }

        if (!tv) {
            item { Section("Appearance") }
            if (android.os.Build.VERSION.SDK_INT >= 31) item {
                Toggle("Colours from my wallpaper", p.wallpaperColours) { p.wallpaperColours = it }
            }
            item { Toggle("Reduce motion", p.reduceMotion) { p.reduceMotion = it } }
        }
        item { Section("Downloads") }
        item { Toggle("Download on Wi-Fi only", p.downloadsWifiOnly) { p.downloadsWifiOnly = it } }
        item {
            val caps = listOf(0, 16, 32, 64, 128)
            Choice("Space downloads may use", caps.map { if (it == 0) "No limit" else "$it GB" },
                caps.indexOf(p.downloadCapGb).coerceAtLeast(0)) { p.downloadCapGb = caps[it] }
        }

        item { Section("This Device") }
        item { DeviceCare(state) }

        item { Section("Library on This Phone") }
        item {
            Note(listOf(state.cacheSync.status.ifEmpty { "Starting…" },
                "A copy of your video libraries is kept here and updated the moment the server changes, " +
                "so libraries open at once and can be browsed with no server in reach.").joinToString("\n"))
        }
        item { Section("Account") }
        session?.let { s ->
            item { Note("${s.userName} on ${s.serverName}\n${s.serverUrl}") }
        }
        item { LButton(primary = false, onClick = { state.signOut() }) { Text("Sign Out") } }
    }
}

private fun Set<String>.toggle(id: String) = if (id in this) this - id else this + id

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleLarge, color = Palette.accent,
        modifier = Modifier.padding(top = 18.dp, bottom = 4.dp))
}

@Composable
private fun Note(text: String) = Text(text, style = MaterialTheme.typography.bodyMedium)

@Composable
private fun Toggle(label: String, on: Boolean, note: String? = null, set: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().focusCard { set(!on) }.padding(vertical = 6.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.titleMedium)
            note?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
        }
        Switch(on, set)
    }
}

/** Updates from the Mac, and a log sent to it when something is wrong. */
@Composable
private fun DeviceCare(state: AppState) {
    val server = state.server ?: return
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var update by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf<app.lumiere.android.Updater.Available?>(null) }
    var note by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf<String?>(null) }
    androidx.compose.runtime.LaunchedEffect(Unit) { update = app.lumiere.android.Updater.check(server) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Note("Lumiere ${app.lumiere.android.AppBuild.versionName}" +
            (update?.let { " · ${it.name} is ready on the Mac" } ?: " · up to date"))
        // One per line: side by side they squeezed, and a label wrapped onto three lines.
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            update?.let {
                LButton(onClick = {
                    note = "Fetching the update…"
                    scope.launch { note = app.lumiere.android.Updater.install(context, server) ?: "Confirm the install on screen." }
                }) { Text("Install Update") }
            }
            LButton(primary = false, onClick = {
                scope.launch {
                    note = if (app.lumiere.android.Diagnostics.send(server)) "Sent to the Mac's server log."
                    else "Couldn't reach the server."
                }
            }) { Text("Send Diagnostics to the Mac") }
            LButton(primary = false, onClick = { state.push(app.lumiere.android.Screen.DiagnosticsView) }) { Text("View Diagnostics") }
        }
        note?.let { Note(it) }
    }
}

@Composable
private fun Choice(label: String, options: List<String>, selected: Int, pick: (Int) -> Unit) {
    Column(Modifier.padding(vertical = 4.dp)) {
        Text(label, style = MaterialTheme.typography.titleMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(options.size) { i -> LChip(i == selected, { pick(i) }, { Text(options[i]) }) }
        }
    }
}

/** Set, change or clear the PIN for Settings and the private room. */
@Composable
private fun DevicePin(state: AppState) {
    val p = state.settings
    var setting by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    Column {
        Note(if (!p.hasPin) "No PIN. On a shared device with no screen lock, a PIN keeps Settings and the private room for you."
            else "A PIN guards Settings and, on a device with no screen lock, the private room.")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LButton(primary = false, onClick = { setting = true }) { Text(if (!p.hasPin) "Set a PIN" else "Change PIN") }
            if (p.hasPin) LButton(primary = false, onClick = { p.clearPin() }) { Text("Remove PIN") }
        }
    }
    if (setting) PinPad("Choose a four-digit PIN", onDone = { p.setPin(it); state.pinOpen = true; setting = false },
        onCancel = { setting = false })
}
