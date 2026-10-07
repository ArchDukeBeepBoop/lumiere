package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.people
import androidx.compose.foundation.layout.Row
import kotlinx.coroutines.delay

/** Films, shows and episodes by name, as you type. */
@Composable
fun SearchScreen(state: AppState) {
    val server = state.server ?: return
    val session = state.session ?: return
    val form = LocalFormFactor.current
    var term by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Item>>(emptyList()) }
    var people by remember { mutableStateOf<List<Item>>(emptyList()) }
    val focus = remember { FocusRequester() }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    LaunchedEffect(term) {
        if (term.trim().length < 2) { results = emptyList(); people = emptyList(); return@LaunchedEffect }
        delay(300)
        results = state.visible(runCatching { server.search(session.userId, term.trim()) }.getOrDefault(emptyList()))
        people = server.people(term.trim())
        // Kept once it has found something, so the recent list holds real searches.
        delay(1500)
        // Never from inside the private room: the list shows outside it.
        if (!state.roomOpen && (results.isNotEmpty() || people.isNotEmpty())) state.settings.rememberSearch(term.trim())
    }

    // The remote's microphone: Google TV and phones answer this with their own
    // speech dialog; the words come back as the search.
    val context = androidx.compose.ui.platform.LocalContext.current
    val speech = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Say a title, a show or a person")
    val canSpeak = remember { speech.resolveActivity(context.packageManager) != null }
    val listen = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { r ->
        r.data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let { term = it }
    }

    Column(Modifier.fillMaxSize().background(Palette.canvas)) {
        if (canSpeak) LButton(primary = false, onClick = { runCatching { listen.launch(speech) } },
            modifier = Modifier.padding(start = form.gutter.dp, top = form.gutter.dp)) { Text("🎤  Search by voice") }
        OutlinedTextField(
            value = term, onValueChange = { term = it }, singleLine = true,
            placeholder = { Text("Search titles, music and people") },
            modifier = Modifier.fillMaxWidth().padding(form.gutter.dp).focusRequester(focus),
        )
        if (term.isBlank() && state.settings.recentSearches.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Text("Recent", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                androidx.compose.material3.TextButton(onClick = { state.settings.clearSearches() }) { Text("Clear") }
            }
            state.settings.recentSearches.forEach { recent ->
                Text(recent, style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.fillMaxWidth().focusCard { term = recent }
                        .padding(horizontal = form.gutter.dp, vertical = 10.dp))
            }
        }
        if (people.isNotEmpty()) {
            androidx.compose.foundation.lazy.LazyRow(
                contentPadding = PaddingValues(horizontal = form.gutter.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(people.size) { i ->
                    val p = people[i]
                    androidx.compose.material3.AssistChip(onClick = { state.push(Screen.Person(p.id, p.name)) },
                        label = { Text("${p.name} · ${p.overview ?: ""}") })
                }
            }
        }
        if (term.trim().length >= 2 && results.isEmpty() && people.isEmpty()) {
            Text("Nothing by that name.", style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = form.gutter.dp))
        }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(form.posterWidth.dp),
            contentPadding = PaddingValues(form.gutter.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            items(results, key = { it.id }) { item ->
                val context = androidx.compose.ui.platform.LocalContext.current
                ItemCard(item, server, CardShape.Poster) {
                    when {
                        item.isAlbum -> state.push(Screen.Album(item.id))
                        item.isAudio -> app.lumiere.android.music.Music.play(context, server, listOf(item), 0, state.roomOpen)
                        else -> state.push(Screen.Detail(item.id))
                    }
                }
            }
        }
    }
}
