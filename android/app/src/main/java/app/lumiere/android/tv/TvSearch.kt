package app.lumiere.android.tv

import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.ui.focus.focusRestorer
import app.lumiere.android.ui.TvPill
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
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

private val keys = ("abcdefghijklmnopqrstuvwxyz1234567890").map { it.toString() } + listOf("␣", "⌫", "Clear")

/**
 * Search with a remote: one line of letters across the top, as tvOS has,
 * and results filling in as each one is pressed. Under it, finished names to
 * jump to; recent searches when nothing is typed. The microphone, where the remote has one, still works.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
fun TvSearchScreen(state: AppState) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val context = LocalContext.current
    var term by remember { mutableStateOf("") }
    // The phone's keyboard types here while Search is open.
    androidx.compose.runtime.DisposableEffect(Unit) {
        app.lumiere.android.remote.RemoteHost.typing = { t -> term = t }
        onDispose { app.lumiere.android.remote.RemoteHost.typing = null }
    }
    var results by remember { mutableStateOf<List<Item>>(emptyList()) }
    var people by remember { mutableStateOf<List<Item>>(emptyList()) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    // Before anything is typed: what was opened lately, private ones left out.
    var opened by remember { mutableStateOf<List<Item>>(emptyList()) }
    LaunchedEffect(Unit) {
        if (!state.roomOpen) opened = state.visible(runCatching { server.byIds(userId, state.settings.recentlyOpened) }.getOrDefault(emptyList()))
            .filter { it.libraryId !in state.privateLibraries }
    }
    LaunchedEffect(term) {
        if (term.trim().length < 2) { results = emptyList(); people = emptyList(); return@LaunchedEffect }
        delay(250)
        results = state.visible(runCatching { server.search(userId, term.trim()) }.getOrDefault(emptyList()))
        people = server.people(term.trim())
        delay(1500)
        if (results.isNotEmpty()) {
            if (state.roomOpen) state.roomSearches = (listOf(term.trim()) + state.roomSearches.filter { it != term.trim() }).take(5)
            else state.settings.rememberSearch(term.trim())
        }
    }
    Column(Modifier.fillMaxSize().background(Palette.canvas).padding(horizontal = 56.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(if (term.isEmpty()) "Search" else term, fontSize = 30.sp, fontWeight = FontWeight.SemiBold,
            color = if (term.isEmpty()) Palette.textMuted else Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        // tvOS's keyboard: one line of letters to sweep along, results filling
        // in below with every press — no on-screen keyboard to open.
        LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            items(keys.size) { i ->
                val k = keys[i]
                TvPill({ term = when (k) { "␣" -> "$term "; "⌫" -> term.dropLast(1); "Clear" -> ""; else -> term + k } },
                    if (i == 0) Modifier.focusRequester(first) else Modifier) {
                    Text(if (k == "Clear") "Clear" else k.uppercase(), fontSize = 18.sp)
                }
            }
        }
        // Finished names to jump to, or what was searched before.
        val hints = if (term.isBlank()) (if (state.roomOpen) state.roomSearches else state.settings.recentSearches.take(5))
            else (people.map { it.name } + results.map { it.seriesName ?: it.name }).distinct().take(5)
        if (hints.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            hints.forEach { h -> TvPill({ term = h }, selected = true) { Text(h, maxLines = 1, overflow = TextOverflow.Ellipsis) } }
        }
        Column(Modifier.fillMaxSize()) {
            if (people.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 12.dp)) {
                people.take(4).forEach { p -> LButton(primary = false, onClick = { open(state, p, context) }) { Text(p.name) } }
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
                                            .focusCard({}, { open(state, r, context) }) { state.actionsFor = r }.background(Palette.surface)) {
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
