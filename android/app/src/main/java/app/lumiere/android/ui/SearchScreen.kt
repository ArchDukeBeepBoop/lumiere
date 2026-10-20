@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.allGenres
import app.lumiere.android.api.people
import app.lumiere.android.api.pictureFor
import coil.compose.AsyncImage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

/** The genre tiles, kept between visits: each pictured by one of its titles. */
private object Categories {
    var tiles by mutableStateOf<List<Pair<String, Item>>>(emptyList())
    var forRoom: Boolean? = null
}

/**
 * Search on a phone, as the Apple TV app's: a large title, iOS's rounded
 * field with the microphone in it, recent searches, and "Browse Categories"
 * — the genres as pictured tiles — until something is typed; then people as
 * circles and Top Results as a list, each row a tap from its page.
 */
@Composable
fun SearchScreen(state: AppState) {
    val server = state.server ?: return
    val session = state.session ?: return
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    var term by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Item>>(emptyList()) }
    var people by remember { mutableStateOf<List<Item>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }

    LaunchedEffect(term) {
        if (term.trim().length < 2) { results = emptyList(); people = emptyList(); searching = false; return@LaunchedEffect }
        searching = true
        delay(300)
        results = state.visible(runCatching { server.search(session.userId, term.trim()) }.getOrDefault(emptyList()))
            .filter { it.id !in state.settings.notInterested }
            // Shows and films first, as Apple ranks them; then music; episodes last.
            .sortedBy { when { it.isSeries || it.type == "Movie" -> 0; it.isAlbum -> 1; it.isAudio -> 2; it.isEpisode -> 4; else -> 3 } }
        people = server.people(term.trim())
        searching = false
        delay(1500)
        // Never from inside the private room: the list shows outside it.
        if (!state.roomOpen && (results.isNotEmpty() || people.isNotEmpty())) state.settings.rememberSearch(term.trim())
    }
    LaunchedEffect(state.roomOpen) {
        if (Categories.tiles.isNotEmpty() && Categories.forRoom == state.roomOpen) return@LaunchedEffect
        Categories.tiles = runCatching {
            coroutineScope {
                server.allGenres(session.userId).take(16).map { name -> async { name to server.pictureFor(session.userId, null, name) } }
                    .awaitAll().mapNotNull { (n, p) -> p?.takeIf { !state.hides(it.libraryId) }?.let { n to it } }
            }
        }.getOrDefault(emptyList())
        Categories.forRoom = state.roomOpen
    }

    val speech = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Say a title, a show or a person")
    val canSpeak = remember { speech.resolveActivity(context.packageManager) != null }
    val listen = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { r ->
        r.data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let { term = it }
    }

    val list = androidx.compose.foundation.lazy.rememberLazyListState()
    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 40.dp)) {
        item { IosLargeTitle("Search") }
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp).height(40.dp).clip(RoundedCornerShape(10.dp))
                .background(Palette.surface).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Search, null, tint = Palette.textSecondary, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(6.dp))
                Box(Modifier.weight(1f)) {
                    if (term.isEmpty()) Text("Shows, Movies, People and More", style = IosType.body, color = Palette.textMuted, maxLines = 1)
                    BasicTextField(term, { term = it }, singleLine = true, textStyle = IosType.body.copy(color = Palette.textPrimary),
                        cursorBrush = SolidColor(Palette.accent),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
                        modifier = Modifier.fillMaxWidth().focusRequester(focus))
                }
                if (term.isNotEmpty()) Icon(Icons.Default.Cancel, "Clear", tint = Palette.textMuted,
                    modifier = Modifier.size(20.dp).clickable { term = "" })
                else if (canSpeak) Icon(Icons.Default.Mic, "Search by voice", tint = Palette.textSecondary,
                    modifier = Modifier.size(22.dp).clickable { runCatching { listen.launch(speech) } })
            }
        }
        if (term.isBlank()) {
            if (state.settings.recentSearches.isNotEmpty()) {
                item {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 22.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Recent Searches", style = IosType.title, color = Palette.textPrimary, modifier = Modifier.weight(1f))
                        Text("Clear", style = IosType.body, color = Palette.accent, modifier = Modifier.clickable { state.settings.clearSearches() })
                    }
                }
                items(state.settings.recentSearches.take(6)) { recent ->
                    Column(Modifier.fillMaxWidth().clickable { term = recent }.padding(start = 16.dp)) {
                        Row(Modifier.padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Search, null, tint = Palette.textMuted, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(10.dp))
                            Text(recent, style = IosType.body, color = Palette.accent)
                        }
                        HorizontalDivider(thickness = 0.5.dp, color = Palette.border)
                    }
                }
            }
            if (Categories.tiles.isNotEmpty()) {
                item { Text("Browse Categories", style = IosType.title, color = Palette.textPrimary,
                    modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 10.dp)) }
                Categories.tiles.chunked(2).forEachIndexed { i, pair ->
                    item(key = "cat-$i") {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            pair.forEach { (name, pic) -> CategoryTile(state, name, pic, Modifier.weight(1f)) }
                            if (pair.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        } else {
            if (people.isNotEmpty()) item {
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    items(people, key = { it.id }) { p ->
                        Column(Modifier.width(76.dp).iosClick { state.push(Screen.Person(p.id, p.name)) },
                            horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(Modifier.size(70.dp).clip(CircleShape).background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
                                Text(p.name.split(' ').mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString(""),
                                    style = IosType.headline, color = Palette.textSecondary)
                                p.primaryTag?.let { AsyncImage(server.imageUrl(p.id, "Primary", it, 200), p.name,
                                    contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) }
                            }
                            Text(p.name, style = IosType.footnote, color = Palette.textPrimary, maxLines = 2,
                                overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        }
                    }
                }
            }
            if (results.isNotEmpty()) item {
                Text("Top Results", style = IosType.title, color = Palette.textPrimary, modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp))
            }
            items(results, key = { it.id }) { r -> ResultRow(state, r) { open(state, r, context) } }
            if (!searching && term.trim().length >= 2 && results.isEmpty() && people.isEmpty()) item {
                Text("No results for “${term.trim()}”", style = IosType.body, color = Palette.textSecondary,
                    modifier = Modifier.fillMaxWidth().padding(32.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
    }
    IosCollapsedTitle(list, "Search")
    }
}

/** A genre as Apple's category tile: a picture, darkened, its name in bold at the foot. */
@Composable
private fun CategoryTile(state: AppState, name: String, pic: Item, modifier: Modifier) {
    val server = state.server ?: return
    Box(modifier.aspectRatio(16f / 10f).clip(RoundedCornerShape(10.dp)).background(Palette.surfaceRaised)
        .iosClick { state.push(Screen.Genre(name)) }) {
        AsyncImage(server.imageUrl(pic.id, "Backdrop", pic.backdropTag, 420), null, contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize())
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.3f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.8f))))
        Text(name, style = IosType.headline, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).padding(10.dp))
    }
}

/** One result as an iOS row: the poster small, the name, what it is; long press for its menu. */
@Composable
private fun ResultRow(state: AppState, item: Item, onClick: () -> Unit) {
    val server = state.server ?: return
    val square = item.isAlbum || item.isAudio
    Column(Modifier.fillMaxWidth().combinedClickable(onLongClick = { if (!square) PhoneMenu.item = item }, onClick = onClick)
        .padding(start = 16.dp)) {
        Row(Modifier.padding(vertical = 8.dp, horizontal = 0.dp), verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(if (square) server.imageUrl(item.albumId ?: item.id, "Primary", null, 160) else imageFor(item, server, CardShape.Poster, 160),
                item.name, contentScale = ContentScale.Crop,
                modifier = Modifier.width(54.dp).aspectRatio(if (square) 1f else 2f / 3f).clip(RoundedCornerShape(6.dp)).background(Palette.surfaceRaised))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f).padding(end = 16.dp)) {
                Text(item.name, style = IosType.headline, color = Palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(kind(item), style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        HorizontalDivider(Modifier.padding(start = 66.dp), thickness = 0.5.dp, color = Palette.border)
    }
}

private fun kind(item: Item): String = when {
    item.isSeries -> listOfNotNull("TV Show", item.year?.toString()).joinToString(" · ")
    item.isEpisode -> listOfNotNull(item.seriesName, episodeShort(item)).joinToString(" · ")
    item.isAlbum -> listOfNotNull("Album", item.albumArtist).joinToString(" · ")
    item.isAudio -> listOfNotNull("Song", item.artists.firstOrNull()).joinToString(" · ")
    item.type == "Movie" -> listOfNotNull("Movie", item.year?.toString()).joinToString(" · ")
    else -> item.year?.toString() ?: item.type
}
