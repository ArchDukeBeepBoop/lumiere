package app.lumiere.android.tv

import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.ui.focus.focusRestorer
import app.lumiere.android.ui.TvPill
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.RecentSearches
import app.lumiere.android.api.Item
import app.lumiere.android.api.people
import app.lumiere.android.api.byIds
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.imageFor
import app.lumiere.android.ui.open
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * The remote's keyboard: the letters in two rows of thirteen and the digits
 * under them, about 970 dp across, so it sits in a TV's middle rather than
 * running off both edges as one long line did; and what each key does to
 * what's typed.
 */
internal object SearchKeys {
    const val SPACE = "␣"
    const val BACK = "⌫"
    const val CLEAR = "Clear"
    const val KEY_DP = 64
    const val GAP_DP = 6

    val rows: List<List<String>> = listOf(
        "abcdefghijklm".map { it.toString() },
        "nopqrstuvwxyz".map { it.toString() },
        "1234567890".map { it.toString() } + listOf(SPACE, BACK, CLEAR),
    )

    /** How many keys' width a key takes: Clear is a word. */
    fun span(key: String): Float = if (key == CLEAR) 2f else 1f

    /** Every row is drawn this wide, its keys sharing it by [span]. */
    val widthDp: Int = rows.maxOf { r -> (r.sumOf { span(it).toDouble() } * KEY_DP).toInt() + (r.size - 1) * GAP_DP }

    fun press(term: String, key: String): String = when (key) {
        SPACE -> "$term "; BACK -> term.dropLast(1); CLEAR -> ""; else -> term + key
    }
}

/**
 * Search with a remote: the letters across the top, as tvOS has, and results
 * filling in as each one is pressed. On a Quest a real field instead, typed
 * on Horizon OS's own keyboard, whose microphone dictates. Under it, finished
 * names to jump to; your recent searches when nothing is typed. A microphone
 * button wherever something on the device can listen.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun TvSearchScreen(state: AppState) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    val quest = app.lumiere.android.AppBuild.quest
    var term by remember { mutableStateOf("") }
    // The Quest's field keeps its own cursor; anything that sets the words
    // from outside (a recent search, the phone, your voice) puts it at the end.
    var field by remember { mutableStateOf(TextFieldValue("")) }
    fun setTerm(t: String) { term = t; field = TextFieldValue(t, TextRange(t.length)) }
    // The phone's keyboard types here while Search is open.
    androidx.compose.runtime.DisposableEffect(Unit) {
        app.lumiere.android.remote.RemoteHost.typing = { t -> setTerm(t) }
        onDispose { app.lumiere.android.remote.RemoteHost.typing = null }
    }
    var results by remember { mutableStateOf<List<Item>>(emptyList()) }
    var people by remember { mutableStateOf<List<Item>>(emptyList()) }
    val first = remember { FocusRequester() }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) {
        runCatching { first.requestFocus() }
        // On a Quest the field opens ready to type: Horizon OS's keyboard comes
        // up under it, once the field has its input connection a frame later.
        if (quest) { androidx.compose.runtime.withFrameNanos { }; runCatching { keyboard?.show() } }
    }
    // Before anything is typed: what was opened lately, private ones left out.
    var opened by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(Unit) {
        if (!state.roomOpen) opened = state.visible(runCatching { server.byIds(userId, state.settings.recentlyOpened) }.getOrDefault(emptyList()))
            .filter { it.libraryId !in state.privateLibraries }
    }
    LaunchedEffect(term) {
        if (term.trim().length < 2) { results = emptyList(); people = emptyList(); return@LaunchedEffect }
        // A pause in the typing, not every letter, asks the Mac.
        delay(300)
        results = state.visible(runCatching { server.search(userId, term.trim()) }.getOrDefault(emptyList()))
        people = server.people(term.trim())
    }
    // A search is kept once it led somewhere: when you open one of its results.
    // In the private room it lasts only as long as the room is open.
    fun keep() {
        val t = term.trim()
        if (t.length < 2) return
        if (state.roomOpen) state.roomSearches = RecentSearches.add(state.roomSearches, t)
        else state.settings.rememberSearch(t)
    }
    val listen = rememberListening { setTerm(it) }
    Column(Modifier.fillMaxSize().background(Palette.canvas).padding(horizontal = 56.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (quest) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                QuestField(field, { field = it; term = it.text }, Modifier.weight(1f, fill = false).focusRequester(first)) {
                    runCatching { keyboard?.hide() }
                }
                listen?.let { Microphone(it) }
            }
            Text("Type, or use the keyboard's microphone to speak", fontSize = 16.sp, color = Palette.textSecondary)
        } else {
            Text(if (term.isEmpty()) "Search" else term, fontSize = 30.sp, fontWeight = FontWeight.SemiBold,
                color = if (term.isEmpty()) Palette.textMuted else Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            // tvOS's keyboard: the letters to sweep along, results filling
            // in below with every press — no on-screen keyboard to open.
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Column(Modifier.focusRestorer().focusGroup(), verticalArrangement = Arrangement.spacedBy(SearchKeys.GAP_DP.dp)) {
                    SearchKeys.rows.forEachIndexed { r, row ->
                        Row(Modifier.width(SearchKeys.widthDp.dp), horizontalArrangement = Arrangement.spacedBy(SearchKeys.GAP_DP.dp)) {
                            row.forEachIndexed { i, k ->
                                TvPill({ term = SearchKeys.press(term, k) },
                                    Modifier.weight(SearchKeys.span(k)).then(if (r == 0 && i == 0) Modifier.focusRequester(first) else Modifier),
                                    shape = RoundedCornerShape(12.dp)) {
                                    Text(if (k == SearchKeys.CLEAR) k else k.uppercase(), fontSize = 18.sp, maxLines = 1,
                                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
                listen?.let { Microphone(it) }
            }
        }
        // When nothing is typed: what you searched for lately, to run again.
        val recent = if (state.roomOpen) state.roomSearches else state.settings.recentSearches
        if (term.isBlank() && recent.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Recent", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = Palette.textSecondary,
                modifier = Modifier.padding(end = 8.dp))
            LazyRow(Modifier.weight(1f, fill = false).focusRestorer(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(recent.size, key = { recent[it] }) { i ->
                    TvPill({ setTerm(recent[i]) }, Modifier.widthIn(max = 320.dp), selected = true) {
                        Text(recent[i], maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            TvPill({ if (state.roomOpen) state.roomSearches = emptyList() else state.settings.clearRecentSearches() }) {
                Text("Clear", maxLines = 1)
            }
        }
        // Finished names to jump to.
        val hints = if (term.isBlank()) emptyList()
            else (people.map { it.name } + results.map { it.seriesName ?: it.name }).distinct().take(5)
        if (hints.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            hints.forEach { h -> TvPill({ setTerm(h) }, selected = true) { Text(h, maxLines = 1, overflow = TextOverflow.Ellipsis) } }
        }
        Column(Modifier.fillMaxSize()) {
            if (people.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 12.dp)) {
                people.take(4).forEach { p -> LButton(primary = false, onClick = { keep(); open(state, p, context) }) { Text(p.name) } }
            }
            if (term.isBlank() && opened.isNotEmpty()) {
                Text("Recently Viewed", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary,
                    modifier = Modifier.padding(bottom = 10.dp))
            }
            if (term.trim().length >= 2 && results.isEmpty() && people.isEmpty()) Text("Nothing by that name.", style = MaterialTheme.typography.bodyMedium)
            // Grouped as Apple's search is: films, shows, episodes, each its own row.
            val shown = if (term.isBlank()) opened else results
            val groups = if (term.isBlank()) listOf("" to shown) else listOf(
                "Movies" to shown.filter { it.type == "Movie" },
                "Shows" to shown.filter { it.isSeries },
                "Episodes" to shown.filter { it.isEpisode },
                "More" to shown.filter { it.type != "Movie" && !it.isSeries && !it.isEpisode },
            ).filter { it.second.isNotEmpty() }
            androidx.compose.foundation.lazy.LazyColumn(contentPadding = PaddingValues(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                groups.forEach { (name, list) ->
                    item(key = "g-$name") {
                        Column {
                            if (name.isNotEmpty()) Text(name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary,
                                modifier = Modifier.padding(bottom = 8.dp))
                            LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(32.dp),
                                contentPadding = PaddingValues(vertical = 10.dp, horizontal = 4.dp)) {
                                items(list.size) { i -> val r = list[i]
                                    var chosen by remember { mutableStateOf(false) }
                                    Column(Modifier.width(if (r.isEpisode) 240.dp else 140.dp).onFocusChanged { chosen = it.hasFocus }) {
                                        Box(Modifier.fillMaxWidth().aspectRatio(if (r.isEpisode) 16f / 9f else 2f / 3f)
                                            .focusCard({}, { keep(); open(state, r, context) }) { state.actionsFor = r }.background(Palette.surface)) {
                                            AsyncImage(imageFor(r, server, if (r.isEpisode) CardShape.Wide else CardShape.Poster, 280), r.name,
                                                contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                        }
                                        Spacer(Modifier.height(6.dp))
                                        Text(if (r.isEpisode) listOfNotNull(r.seriesName, r.episodeLabel).joinToString(" · ") else r.name, maxLines = 1,
                                            overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium.copy(color = Palette.textPrimary),
                                            modifier = Modifier.alpha(if (chosen || r.isEpisode) 1f else 0f))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * The Quest's search field: Horizon OS's keyboard types in it, and its
 * microphone key dictates. The thumbstick still moves on, up to the tabs
 * and down to the results; pointing at the field only looks, a press types.
 */
@Composable
private fun QuestField(value: TextFieldValue, onChange: (TextFieldValue) -> Unit, modifier: Modifier, onSearch: () -> Unit) {
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    androidx.compose.material3.OutlinedTextField(value, onChange, singleLine = true,
        placeholder = { Text("Films, shows and people", fontSize = 22.sp) },
        leadingIcon = { androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Filled.Search, null, tint = Palette.textSecondary) },
        textStyle = androidx.compose.ui.text.TextStyle(fontSize = 22.sp, color = Palette.textPrimary),
        shape = RoundedCornerShape(28.dp),
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Palette.textPrimary, unfocusedBorderColor = Palette.textMuted,
            focusedContainerColor = Palette.surface, unfocusedContainerColor = Palette.surface, cursorColor = Palette.accent,
            focusedTextColor = Palette.textPrimary, unfocusedTextColor = Palette.textPrimary),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search),
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { onSearch() }),
        modifier = modifier.widthIn(max = 900.dp).fillMaxWidth().heightIn(min = 60.dp).onPreviewKeyEvent { e ->
            if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
            when (e.nativeKeyEvent.keyCode) {
                android.view.KeyEvent.KEYCODE_DPAD_UP -> focusManager.moveFocus(androidx.compose.ui.focus.FocusDirection.Up)
                android.view.KeyEvent.KEYCODE_DPAD_DOWN -> focusManager.moveFocus(androidx.compose.ui.focus.FocusDirection.Down)
                else -> false
            }
        })
}

/** Speak a search, where the remote or the device has a recogniser. */
@Composable
private fun Microphone(listen: () -> Unit) {
    LButton(primary = false, onClick = listen) {
        androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Filled.Mic, null)
        Spacer(Modifier.width(8.dp))
        Text("Speak", maxLines = 1)
    }
}

/**
 * Listening for a search: Google TV and most phones answer with their own
 * speech dialog, and its best guess comes back to [onHeard]. Null where
 * nothing on the device can listen, as on most Quests, whose keyboard
 * dictates instead; then no microphone is shown at all.
 */
@Composable
private fun rememberListening(onHeard: (String) -> Unit): (() -> Unit)? {
    val context = LocalContext.current
    val speech = remember {
        android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Search Lumiere")
    }
    val canSpeak = remember { runCatching { speech.resolveActivity(context.packageManager) != null }.getOrDefault(false) }
    val heard by rememberUpdatedState(onHeard)
    val launcher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { r ->
        RecentSearches.heard(r.data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS))?.let { heard(it) }
    }
    return if (!canSpeak) null else remember(launcher) { { runCatching { launcher.launch(speech) }; Unit } }
}
