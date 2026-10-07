package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.ServerLibrary
import app.lumiere.android.api.libraries
import app.lumiere.android.api.setMetadataKey
import kotlinx.coroutines.launch

private val steps = listOf("Welcome", "Libraries", "Rooms", "Posters & Details", "Make It Yours", "Ready")

/**
 * The first-run guide, on the phone and the TV alike: libraries and their
 * folders, the rooms, the movie database key, and a few first choices. Opens
 * by itself on a server with no libraries; Settings › Your Setup reopens it.
 */
@Composable
fun SetupScreen(state: AppState) {
    var step by remember { mutableIntStateOf(0) }
    val form = LocalFormFactor.current
    fun finish() { state.settings.setupDone = true; state.pop() }

    Column(Modifier.fillMaxSize().background(Palette.canvas).verticalScroll(rememberScrollState())
        .padding(horizontal = form.gutter.dp, vertical = 24.dp)) {
        Column(Modifier.widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Step ${step + 1} of ${steps.size} · ${steps[step]}", style = MaterialTheme.typography.labelLarge, color = Palette.accent)
            when (step) {
                0 -> Welcome()
                1 -> { Heading("Add your libraries", "A library is a shelf of one kind of thing — Films, TV Shows, Anime, Music — fed by one or more folders on the server's disk.")
                    LibrariesEditor(state, showsRoom = false) }
                2 -> Rooms(state)
                3 -> Details(state)
                4 -> Choices(state)
                else -> Heading("You're ready", "Lumiere is reading your folders now. Titles appear as they're found, and posters follow. Settings › Your Setup brings this guide back, lists your libraries and folders, and everything you've changed.")
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (step > 0) LButton(primary = false, onClick = { step-- }) { Text("Back") }
                LButton(onClick = { if (step < steps.lastIndex) step++ else finish() }) {
                    Text(when (step) { 0 -> "Get Started"; steps.lastIndex -> "Start Watching"; else -> "Continue" })
                }
                if (step < steps.lastIndex) LButton(primary = false, onClick = ::finish) { Text("Finish Later") }
            }
        }
    }
}

@Composable
private fun Heading(title: String, detail: String) {
    Text(title, style = MaterialTheme.typography.headlineMedium)
    Text(detail, style = MaterialTheme.typography.bodyLarge)
}

@Composable
private fun Welcome() {
    Heading("Welcome to Lumiere", "Your films, shows and music from your own disks, on your Mac, phone and TV. A few minutes here and the library is ready.")
    listOf(
        "Add your libraries" to "Point Lumiere at the folders that hold your media. Nothing is moved, renamed or uploaded.",
        "Choose your rooms" to "Keep some libraries in a Private Room that stays out of sight until you open it.",
        "Fill in the details" to "Posters, synopses, cast and collections come from The Movie Database.",
        "Make it yours" to "A few choices now. Everything else, and everything here, lives in Settings.",
    ).forEach { (title, note) ->
        Column { Text(title, style = MaterialTheme.typography.titleMedium); Text(note, style = MaterialTheme.typography.bodyMedium) }
    }
}

@Composable
private fun Rooms(state: AppState) {
    val scope = rememberCoroutineScope()
    var libraries by remember { mutableStateOf<List<ServerLibrary>>(emptyList()) }
    LaunchedEffect(Unit) { libraries = runCatching { state.server!!.libraries() }.getOrDefault(emptyList()) }
    Heading("Choose your rooms", "The Main Room is what anyone sees. The Private Room holds the libraries you'd rather keep to yourself: they stay off Home, search and Continue Watching until you open the room.")
    if (libraries.isEmpty()) Text("Add a library first, then choose its room here.", style = MaterialTheme.typography.bodyMedium)
    libraries.forEach { library ->
        val on = library.id in state.privateLibraries
        SetupToggle(library.name, if (on) "In the Private Room" else "In the Main Room", on) { scope.launch { setPrivate(state, library.id, it) } }
    }
    val p = state.settings
    SetupToggle("Ask to unlock the Private Room", "Your fingerprint, face or a PIN.", p.roomRequiresUnlock) { p.roomRequiresUnlock = it }
    SetupToggle("Blur its covers", "Posters stay blurred until a title is opened.", p.roomBlursCovers) { p.roomBlursCovers = it }
}

@Composable
private fun Details(state: AppState) {
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var note by remember { mutableStateOf<String?>(null) }
    Heading("Posters & details", "Lumiere fills in posters, synopses, cast and film series from The Movie Database (TMDB) with a free key of your own. It is kept by your server, never shown again.")
    Text("1. Make a free account at themoviedb.org.\n2. In its Settings › API, request a key.\n3. Paste the long “API Read Access Token” here.",
        style = MaterialTheme.typography.bodyMedium)
    OutlinedTextField(token, { token = it }, label = { Text("API Read Access Token") }, singleLine = true,
        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        modifier = Modifier.fillMaxWidth())
    LButton(enabled = token.isNotBlank(), onClick = {
        scope.launch {
            note = runCatching { state.server!!.setMetadataKey(token.trim()) }
                .fold({ token = ""; "Saved. The server is filling in your libraries now." }, { "Couldn't save it: ${it.message}" })
        }
    }) { Text("Save Key") }
    note?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
    Text("No key? Everything still works: titles come from the filenames, and pictures from the videos themselves.",
        style = MaterialTheme.typography.labelMedium)
}

@Composable
private fun Choices(state: AppState) {
    val p = state.settings
    Heading("Make it yours", "A few choices to start with. Each, and many more, is in Settings, which also lists everything you've changed.")
    SetupToggle("Play the next episode automatically", null, p.playsNext) { p.playsNext = it }
    SetupToggle("Skip intros without asking", null, p.skipsIntros) { p.skipsIntros = it }
    SetupToggle("Subtitles on", null, p.subtitlesOn) { p.subtitlesOn = it }
    SetupToggle("Anime in Japanese with English subtitles", "In any library named Anime.", p.animeJapanese) { p.animeJapanese = it }
    if (LocalFormFactor.current.isTv) SetupToggle("One Up Next row", null, p.tvUpNextMerged) { p.tvUpNextMerged = it }
    else SetupToggle("Download on Wi-Fi only", null, p.downloadsWifiOnly) { p.downloadsWifiOnly = it }
}

@Composable
private fun SetupToggle(label: String, note: String?, on: Boolean, set: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().focusCard { set(!on) }.padding(vertical = 6.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.titleMedium)
            note?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
        }
        Switch(on, set)
    }
}
