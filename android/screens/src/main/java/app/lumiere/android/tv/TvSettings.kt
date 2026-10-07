package app.lumiere.android.tv

import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Diagnostics
import app.lumiere.android.Prefs
import app.lumiere.android.Screen
import app.lumiere.android.Updater
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.PinPad
import app.lumiere.android.ui.focusCard
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

/** One setting: a switch, a choice from a list, an action, or something drawn by hand. */
private sealed class Opt(val title: String, val note: String) {
    class Toggle(title: String, note: String, val get: () -> Boolean, val set: (Boolean) -> Unit) : Opt(title, note)
    class Pick(title: String, note: String, val labels: List<String>, val get: () -> Int,
               val preview: Preview? = null, val set: (Int) -> Unit) : Opt(title, note)
    class Action(title: String, note: String, val run: () -> Unit) : Opt(title, note)
    class Custom(title: String, note: String, val draw: @Composable () -> Unit) : Opt(title, note)
}
private enum class Preview { Subtitles, Tone }

private class Category(val name: String, val options: List<Opt>)

/**
 * Settings as tvOS lays them out: categories down the left, the chosen one's
 * settings on the right, each with a line saying what it does. A choice opens
 * its list with a tick by the current one; subtitles and picture tone show a
 * live sample as they change; Home's rows are picked up and moved with OK.
 */
@Composable
fun TvSettingsScreen(state: AppState) {
    val p = state.settings
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var update by remember { mutableStateOf<Updater.Available?>(null) }
    var note by remember { mutableStateOf<String?>(null) }
    var settingPin by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { state.server?.let { update = Updater.check(it) } }

    val categories = listOf(
        Category("Your Setup", listOf(
            Opt.Action("Open the Setup Guide", "Libraries, rooms, posters and a few first choices, step by step.") { state.push(app.lumiere.android.Screen.Setup) },
            Opt.Custom("Libraries & Folders", "Every library on the server and the folders it reads.") { app.lumiere.android.ui.LibrariesEditor(state) },
            Opt.Custom("Your Changes", "Every setting that differs from how Lumiere comes.") { app.lumiere.android.ui.YourChangesList(state) },
        )),
        Category("Playback", listOf(
            Opt.Toggle("Play the next episode automatically", "Up Next counts down in the credits and goes on.", { p.playsNext }) { p.playsNext = it },
            Opt.Pick("Ask \u201CStill watching?\u201D", "After this many episodes in a row with nobody pressing anything.",
                listOf("Never", "After 2", "After 3", "After 4", "After 5", "After 8"),
                { listOf(0, 2, 3, 4, 5, 8).indexOf(p.stillWatchingAfter).coerceAtLeast(0) }) { p.stillWatchingAfter = listOf(0, 2, 3, 4, 5, 8)[it] },
            Opt.Toggle("Skip intros without asking", "Otherwise Skip Intro is offered.", { p.skipsIntros }) { p.skipsIntros = it },
            Opt.Toggle("Skip Intro counts down by itself", "Six seconds, then it skips; Back keeps the intro.", { p.skipCountdown }) { p.skipCountdown = it },
            Opt.Toggle("Anime in Japanese with English subtitles", "In any library named Anime.", { p.animeJapanese }) { p.animeJapanese = it },
        )),
        Category("Subtitles & Sound", listOf(
            Opt.Toggle("Subtitles on", "Off still shows forced subtitles for foreign lines.", { p.subtitlesOn }) { p.subtitlesOn = it },
            Opt.Toggle("Burn anime subtitles into the picture", "Looks like hardcoded subtitles; heavier, and some 10-bit files refuse it.",
                { p.burnsInSubtitles }) { p.burnsInSubtitles = it },
            Opt.Pick("Plain subtitle size", "For SRT and other unstyled subtitles.", listOf("Small", "Medium", "Large", "Extra large"),
                { p.subtitleSize }, Preview.Subtitles) { p.subtitleSize = it },
            Opt.Pick("Plain subtitle look", "Outline and shadow need no box.", listOf("Outline", "Shadow", "Dark box"),
                { p.subtitleStyle }, Preview.Subtitles) { p.subtitleStyle = it },
            Opt.Pick("Dialogue boost", "Louder for small projector speakers.", listOf("Off", "+3 dB", "+6 dB", "+9 dB"),
                { p.dialogueBoost / 3 }) { p.dialogueBoost = it * 3 },
            Opt.Toggle("Night sound", "Loud scenes quieter, quiet ones louder.", { p.nightSound }) { p.nightSound = it },
        )),
        Category("Picture & Text", listOf(
            Opt.Pick("Picture tone", "A light tint for projectors that run blue or yellow.", listOf("Neutral", "Warmer", "Cooler"),
                { p.pictureTone }, Preview.Tone) { p.pictureTone = it },
            Opt.Pick("Subtitle language", "Chosen first when a title has several, and fetched when it has none.",
                listOf("English", "French", "Spanish", "German", "Italian", "Portuguese", "Japanese"),
                { listOf("en", "fr", "es", "de", "it", "pt", "ja").indexOf(p.subtitleLanguage).coerceAtLeast(0) }) {
                p.subtitleLanguage = listOf("en", "fr", "es", "de", "it", "pt", "ja")[it] },
            Opt.Toggle("Night sound after 10 pm", "From 10 pm to 6 am, loud scenes softer and voices a little clearer, by themselves.",
                { p.nightAuto }) { p.nightAuto = it },
            Opt.Toggle("Warmer picture for films", "Films play with the warm tone; shows and anime keep the one above.",
                { p.filmsWarm }) { p.filmsWarm = it },
            Opt.Toggle("Lamp at full brightness during films", "The device's own level returns after.", { p.lampBright }) { p.lampBright = it },
            Opt.Pick("Text size", "Larger for a screen read from across the room.", listOf("Normal", "Larger", "Largest"),
                { p.textScale }) { p.textScale = it },
            Opt.Toggle("Reduce motion", "No tilt, light sweep or drifting; quick fades. On by default where memory is short.",
                { p.reduceMotion }) { p.reduceMotion = it },
            Opt.Toggle("Clock in the corner", "On Home, in a paused film and the screensaver.", { p.showsClock }) { p.showsClock = it },
            Opt.Toggle("Darker menus from 10 pm to 6 am", "So a projected menu does not light the room.", { p.dimsAtNight }) { p.dimsAtNight = it },
            Opt.Pick("Screensaver after", "Your backdrops drifting, after this long still on a menu.", listOf("Never", "2 min", "5 min", "10 min", "30 min"),
                { listOf(0, 2, 5, 10, 30).indexOf(p.screensaverMinutes).coerceAtLeast(0) }) { p.screensaverMinutes = listOf(0, 2, 5, 10, 30)[it] },
        )),
        Category("Home", listOf(
            Opt.Toggle("Tabs along the top", "tvOS style: up from the spotlight shows them. Off: a menu on the left after Back.",
                { p.tvTopBar }) { p.tvTopBar = it },
            Opt.Toggle("One Up Next row", "In progress, next episodes and nearly-finished seasons together, as the Apple TV app shows them.",
                { p.tvUpNextMerged }) { p.tvUpNextMerged = it },
            Opt.Toggle("Spotlight previews", "A silent clip plays in the spotlight after a few seconds. Uses more memory; off on this device unless chosen.",
                { p.bannerPreviews }) { p.bannerPreviews = it },
            Opt.Toggle("Sound as the remote moves", "A soft tick on each move, as Apple TV makes. Uses the projector's own click sound.",
                { p.focusSound }) { p.focusSound = it },
            Opt.Pick("Posters across in Library", "More fit smaller posters on the screen.", listOf("6", "7", "8", "10"),
                { listOf(6, 7, 8, 10).indexOf(p.libraryColumns).coerceAtLeast(1) }) { p.libraryColumns = listOf(6, 7, 8, 10)[it] },
            Opt.Toggle("Episodes open their own page", "Choosing an episode shows its story and Play first. Off: it plays at once.",
                { p.episodesOpenPage }) { p.episodesOpenPage = it },
            Opt.Toggle("Hide spoilers", "Episodes not yet watched show their number only — no name, no story.",
                { p.hidesSpoilers }) { p.hidesSpoilers = it },
            Opt.Toggle("Compact Home", "Only the first six rows, quicker on this projector's memory. The rest stay in Rows below.",
                { p.compactHome }) { p.compactHome = it },
            Opt.Custom("Rows", "OK picks a row up; up and down move it; OK puts it down. Menu switches it on or off.") { HomeOrder(p) },
            Opt.Action("Show the remote tour again", "The three cards from the first open.") { p.tvTourShown = false; state.tab(Screen.Home) },
        )),
        Category("Private Room", listOf(
            Opt.Toggle("Same private libraries as the Mac", "Set in Lumiere's Settings on the Mac, under Privacy.",
                { p.privateFollowsMac }) { p.privateFollowsMac = it },
            Opt.Toggle("Ask for the device's lock to open it", "With no screen lock, the PIN below is asked instead.",
                { p.roomRequiresUnlock }) { p.roomRequiresUnlock = it },
            Opt.Pick("Shut the room after leaving the app", "At once is safest.", listOf("At once", "1 min", "5 min", "15 min", "1 hour", "Never"),
                { listOf(0, 1, 5, 15, 60, -1).indexOf(p.roomLockMinutes).coerceAtLeast(0) }) { p.roomLockMinutes = listOf(0, 1, 5, 15, 60, -1)[it] },
            Opt.Toggle("Grey palette inside", "So it is plain which space is open.", { p.roomUsesOwnTheme }) { p.roomUsesOwnTheme = it },
            Opt.Toggle("Blur covers in lists", "Off: covers shown clearly. On: blurred in lists, clear on a title's own page.",
                { p.tvBlursCovers }) { p.tvBlursCovers = it; if (state.roomOpen) app.lumiere.android.ui.RoomTheme.blursCovers = it },
            Opt.Toggle("Block screenshots inside", "No screenshots, recordings or app-switcher preview.", { p.roomBlocksCapture }) { p.roomBlocksCapture = it },
            Opt.Action(if (p.devicePin.isEmpty()) "Set a device PIN" else "Change the device PIN",
                "Guards Settings, and the room on a device with no screen lock.") { settingPin = true },
        )),
        Category("This Device", listOf(
            Opt.Action(update?.let { "Install update ${it.name}" } ?: "Lumiere ${app.lumiere.android.AppBuild.versionName} — up to date",
                "New versions come from the Mac.") {
                val s = state.server ?: return@Action
                if (update != null) scope.launch { note = "Fetching the update…"; note = Updater.install(context, s) ?: "Confirm the install on screen." }
            },
            Opt.Pick("Space downloads may use", "A download that would go past it is refused, with a word why. The projector has 16 GB in all.",
                listOf("No limit", "2 GB", "4 GB", "8 GB", "12 GB"),
                { listOf(0, 2, 4, 8, 12).indexOf(p.downloadCapGb).coerceAtLeast(0) }) { p.downloadCapGb = listOf(0, 2, 4, 8, 12)[it] },
            Opt.Toggle("Keep next episodes ready", "The next two episodes of what is playing are saved here, within the space above, so a sleeping Mac doesn't stop the evening.",
                { p.keepNextReady }) { p.keepNextReady = it },
            run {
                val free = context.filesDir.usableSpace / 1_000_000_000.0
                val used = state.downloads.usedBytes() / 1_000_000_000.0
                Opt.Action("Free up space", "%.1f GB free · downloads use %.1f GB. Removes downloads already watched.".format(free, used)) {
                    val s = state.server ?: return@Action
                    val u = state.session?.userId ?: return@Action
                    scope.launch {
                        var n = 0
                        for (d in state.downloads.all.toList()) {
                            if (runCatching { s.item(u, d.id) }.getOrNull()?.played == true) { state.downloads.remove(d.id); n++ }
                        }
                        note = if (n == 0) "Nothing watched to remove." else "Removed $n watched download${if (n == 1) "" else "s"}."
                    }
                }
            },
            Opt.Toggle("Download on Wi-Fi only", "Not over a phone's mobile data or a hotspot that charges.",
                { p.downloadsWifiOnly }) { p.downloadsWifiOnly = it },
            Opt.Custom("About this device", "") {
                val am = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val mem = android.app.ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
                val ip = runCatching { java.net.NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }
                    .firstOrNull { !it.isLoopbackAddress && it is java.net.Inet4Address }?.hostAddress }.getOrNull()
                Text(listOf(
                    "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL} · Android ${android.os.Build.VERSION.RELEASE}",
                    "Memory: %.1f GB free of %.1f GB".format(mem.availMem / 1e9, mem.totalMem / 1e9),
                    "Storage: %.1f GB free".format(context.filesDir.usableSpace / 1e9),
                    "This device: ${ip ?: "no network"} · the Mac: ${state.session?.serverUrl ?: "not signed in"}",
                    "Lumiere ${app.lumiere.android.AppBuild.versionName}",
                ).joinToString("\n"), style = MaterialTheme.typography.bodyMedium)
            },
            Opt.Toggle("Phone as remote", "Phones with Lumiere on this Wi-Fi can pair with a code shown here, then steer this TV.",
                { p.phoneRemote }) { p.phoneRemote = it },
            Opt.Action("Pair a phone now", "Shows a code here; enter it in Lumiere on the phone under TV Remote.") {
                app.lumiere.android.remote.RemoteHost.pairNow(); note = "Code shown at the top right." },
            Opt.Action("Forget paired phones", "Each phone must pair again with a new code.") {
                app.lumiere.android.remote.RemoteHost.forgetAll(context); note = "Paired phones forgotten." },
            Opt.Action("Send diagnostics to the Mac", "This device's recent log, into the Mac's server log.") {
                val s = state.server ?: return@Action
                scope.launch { note = if (Diagnostics.send(s)) "Sent." else "Couldn't reach the server." }
            },
            Opt.Action("View diagnostics", "What would be sent, readable here.") { state.push(Screen.DiagnosticsView) },
        )),
        Category("Account", listOf(
            Opt.Custom("Signed in", "") { Text("${state.session?.userName} on ${state.session?.serverName}\n${state.session?.serverUrl}",
                style = MaterialTheme.typography.bodyMedium) },
            Opt.Action("Sign out", "This device only.") { state.signOut() },
        )),
    )

    var category by remember { mutableStateOf(0) }
    var picking by remember { mutableStateOf<Opt.Pick?>(null) }
    var search by remember { mutableStateOf("") }
    val firstCategory = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { firstCategory.requestFocus() } }

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        Row(Modifier.fillMaxSize().padding(40.dp), horizontalArrangement = Arrangement.spacedBy(32.dp)) {
            Column(Modifier.width(280.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Settings", style = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                    modifier = Modifier.padding(bottom = 14.dp))
                categories.forEachIndexed { i, c ->
                    val on = i == category && search.isBlank()
                    app.lumiere.android.ui.TvPill({ category = i; picking = null; search = "" },
                        Modifier.fillMaxWidth().then(if (i == 0) Modifier.focusRequester(firstCategory) else Modifier)
                            .onFocusChanged { if (it.isFocused) { category = i; picking = null } }, selected = on) {
                        Text(c.name, style = MaterialTheme.typography.titleMedium)
                    }
                }
                // Search sits under the categories, out of the way of right
                // and down; the D-pad always moves on out of it.
                val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
                OutlinedTextField(search, { search = it; picking = null }, singleLine = true, placeholder = { Text("Search settings") },
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp).onPreviewKeyEvent { e ->
                        if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                        when (e.nativeKeyEvent.keyCode) {
                            android.view.KeyEvent.KEYCODE_DPAD_UP -> focusManager.moveFocus(androidx.compose.ui.focus.FocusDirection.Up)
                            android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> focusManager.moveFocus(androidx.compose.ui.focus.FocusDirection.Right)
                            android.view.KeyEvent.KEYCODE_DPAD_DOWN -> true
                            else -> false
                        }
                    })
            }
            Column(Modifier.fillMaxSize()) {
                val shown = if (search.isBlank()) categories[category].options
                    else categories.flatMap { it.options }.filter { it.title.contains(search, true) || it.note.contains(search, true) }
                val pick = picking
                if (pick?.preview != null) PreviewPane(state, pick.preview)
                if (pick != null) {
                    PickList(pick) { picking = null }
                } else {
                    if (shown.any { it is Opt.Pick && it.preview != null } && search.isBlank()) {
                        (shown.first { it is Opt.Pick && it.preview != null } as Opt.Pick).preview?.let { PreviewPane(state, it) }
                    }
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(shown, key = { it.title }) { o -> OptionRow(o) { if (o is Opt.Pick) picking = o } }
                    }
                }
                note?.let { Text(it, color = Palette.accent, modifier = Modifier.padding(top = 8.dp)) }
            }
        }
        if (settingPin) PinPad("Choose a four-digit PIN", onDone = { p.devicePin = it; state.pinOpen = true; settingPin = false },
            onCancel = { settingPin = false })
    }
}

@Composable
private fun OptionRow(o: Opt, open: () -> Unit) {
    // A custom row holds its own controls (Home's rows, the account): a quiet
    // box around them, not a pill that turns the whole block white.
    if (o is Opt.Custom) {
        Column(Modifier.fillMaxWidth().background(Palette.surfaceRaised, RoundedCornerShape(26.dp)).padding(horizontal = 18.dp, vertical = 12.dp)) {
            Text(o.title, style = MaterialTheme.typography.titleMedium)
            if (o.note.isNotEmpty()) Text(o.note, style = MaterialTheme.typography.labelMedium)
            Box(Modifier.padding(top = 8.dp)) { o.draw() }
        }
        return
    }
    app.lumiere.android.ui.TvPill({
        when (o) {
            is Opt.Toggle -> o.set(!o.get())
            is Opt.Pick -> open()
            is Opt.Action -> o.run()
            is Opt.Custom -> Unit
        }
    }, Modifier.fillMaxWidth(), selected = true, shape = RoundedCornerShape(26.dp)) {
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(o.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            when (o) {
                is Opt.Toggle -> Text(if (o.get()) "On" else "Off", color = app.lumiere.android.ui.pillTint(if (o.get()) Palette.accent else Palette.textMuted))
                is Opt.Pick -> Text(o.labels.getOrNull(o.get()) ?: "", color = app.lumiere.android.ui.pillTint(Palette.accent))
                is Opt.Action -> Text("›", color = app.lumiere.android.ui.pillTint(Palette.textMuted))
                is Opt.Custom -> Unit
            }
        }
        // The explanation only on the chosen setting: the list reads as names.
        if (o.note.isNotEmpty() && app.lumiere.android.ui.LocalPillFocused.current) Text(o.note, style = MaterialTheme.typography.labelMedium,
            color = androidx.compose.material3.LocalContentColor.current.copy(alpha = 0.7f))
        if (o is Opt.Custom) Box(Modifier.padding(top = 8.dp)) { o.draw() }
    }
    }
}

/** A choice's list, the current one ticked; OK chooses and returns, Back returns. */
@Composable
private fun PickList(o: Opt.Pick, done: () -> Unit) {
    val focus = remember { FocusRequester() }
    androidx.activity.compose.BackHandler(onBack = done)
    LaunchedEffect(o) { runCatching { focus.requestFocus() } }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(o.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 6.dp))
        o.labels.forEachIndexed { i, label ->
            val on = i == o.get()
            app.lumiere.android.ui.TvPill({ o.set(i); done() },
                Modifier.fillMaxWidth().then(if (on) Modifier.focusRequester(focus) else Modifier)
                    .onFocusChanged { if (it.isFocused) o.set(i) }, selected = on) {
                Text((if (on) "✓   " else "     ") + label, style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

/** A sample line over one of your backdrops, styled as the setting now stands; picture tone tints it. */
@Composable
private fun PreviewPane(state: AppState, kind: Preview) {
    val server = state.server ?: return
    val p = state.settings
    val pic = state.saverPool.firstOrNull { it.backdropTag != null }
    Box(Modifier.fillMaxWidth(0.6f).aspectRatio(16f / 9f).padding(bottom = 12.dp).background(Color.Black, RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.BottomCenter) {
        pic?.let { AsyncImage(server.imageUrl(it.id, "Backdrop", it.backdropTag, 640), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
        when (p.pictureTone) { 1 -> Box(Modifier.fillMaxSize().background(Color(0x14FF8A00))); 2 -> Box(Modifier.fillMaxSize().background(Color(0x1200A0FF))) }
        if (kind == Preview.Subtitles) {
            val size = listOf(13, 16, 19, 22)[p.subtitleSize.coerceIn(0, 3)].sp
            Text("I've never seen anything like it.", modifier = Modifier.padding(14.dp)
                .then(if (p.subtitleStyle == 2) Modifier.background(Color.Black.copy(alpha = 0.66f)).padding(horizontal = 6.dp) else Modifier),
                style = TextStyle(fontSize = size, fontWeight = FontWeight.Medium, color = Color.White,
                    shadow = when (p.subtitleStyle) { 0 -> Shadow(Color.Black, blurRadius = 3f); 1 -> Shadow(Color.Black, androidx.compose.ui.geometry.Offset(2f, 2f), 4f); else -> null }))
        }
    }
}

/** Home's rows: OK picks one up, up and down move it, OK puts it down; Menu switches it on or off. */
@Composable
private fun HomeOrder(p: Prefs) {
    var moving by remember { mutableStateOf<String?>(null) }
    val order = p.tvRowOrder
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        order.forEachIndexed { i, key ->
            val name = Prefs.TV_ROW_NAMES[key] ?: key
            val hidden = key in p.tvRowsHidden
            Text((if (moving == key) "⇅  " else if (hidden) "○  " else "●  ") + name + if (hidden) "  (off)" else "",
                style = MaterialTheme.typography.titleMedium,
                color = when { moving == key -> Palette.accent; hidden -> Palette.textMuted; else -> Palette.textPrimary },
                modifier = Modifier.fillMaxWidth()
                    .onPreviewKeyEvent { e ->
                        val code = e.nativeKeyEvent.keyCode
                        if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                        when {
                            moving == key && code == android.view.KeyEvent.KEYCODE_DPAD_UP && i > 0 -> {
                                p.tvRowOrder = order.toMutableList().apply { add(i - 1, removeAt(i)) }; true }
                            moving == key && code == android.view.KeyEvent.KEYCODE_DPAD_DOWN && i < order.lastIndex -> {
                                p.tvRowOrder = order.toMutableList().apply { add(i + 1, removeAt(i)) }; true }
                            code == android.view.KeyEvent.KEYCODE_MENU -> {
                                p.tvRowsHidden = if (hidden) p.tvRowsHidden - key else p.tvRowsHidden + key; true }
                            else -> false
                        }
                    }
                    .focusCard({}, { moving = if (moving == key) null else key }) {
                        p.tvRowsHidden = if (hidden) p.tvRowsHidden - key else p.tvRowsHidden + key
                    }
                    .padding(horizontal = 10.dp, vertical = 6.dp))
        }
    }
}
