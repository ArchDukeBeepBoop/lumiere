package app.lumiere.android.tv

import app.lumiere.android.ui.holdsRemote
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Artwork
import app.lumiere.android.api.Candidate
import app.lumiere.android.api.Item
import app.lumiere.android.api.addToCollection
import app.lumiere.android.api.addToPlaylist
import app.lumiere.android.api.applyArtwork
import app.lumiere.android.api.collections
import app.lumiere.android.api.deleteFile
import app.lumiere.android.api.hideFromContinueWatching
import app.lumiere.android.api.identifyApply
import app.lumiere.android.api.identifySearch
import app.lumiere.android.api.itemJson
import app.lumiere.android.api.newCollection
import app.lumiere.android.api.newPlaylist
import app.lumiere.android.api.playlists
import app.lumiere.android.api.refreshMetadata
import app.lumiere.android.api.remoteArtwork
import app.lumiere.android.api.removeArtwork
import app.lumiere.android.api.removeFromLibrary
import app.lumiere.android.api.setFavorite
import app.lumiere.android.api.useFrameFromFile
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import app.lumiere.android.ui.ignoreHeldOk
import app.lumiere.android.ui.frosted
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

private sealed interface Page {
    data object Menu : Page
    data object Playlist : Page
    data object Collection : Page
    data object Identify : Page
    data object Artwork : Page
    data class Confirm(val title: String, val note: String, val label: String, val run: suspend () -> Unit) : Page
}

/**
 * A card's actions — everything the Mac's right-click menu offers, for a
 * remote: playing, the show it belongs to, watched and favourites, Continue
 * Watching, playlists and collections, downloading, the title's details and
 * artwork, and taking it out of the library. Destructive ones ask first.
 */
@Composable
fun TvActions(state: AppState) {
    val item = state.actionsFor ?: return
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    var page by remember(item.id) { mutableStateOf<Page>(Page.Menu) }
    var note by remember(item.id) { mutableStateOf<String?>(null) }
    fun close(changed: Boolean = true) { state.actionsFor = null; if (changed) state.homeRefresh++ }
    fun act(done: String, block: suspend () -> Unit) = scope.launch {
        note = "Working…"
        runCatching { block() }.onSuccess { note = done; kotlinx.coroutines.delay(700); close() }
            .onFailure { note = "Couldn't: ${it.message}" }
    }
    androidx.activity.compose.BackHandler { if (page != Page.Menu) page = Page.Menu else close(false) }

    Box(Modifier.fillMaxSize().ignoreHeldOk().background(Color.Black.copy(alpha = 0.7f)), contentAlignment = Alignment.CenterEnd) {
        Column(Modifier.holdsRemote().fillMaxHeight().width(460.dp).padding(24.dp).frosted().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // The title held, larger, with what it is about — before what can be done with it.
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                coil.compose.AsyncImage(app.lumiere.android.ui.imageFor(item, server, app.lumiere.android.ui.CardShape.Poster, 200), null,
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.width(84.dp).aspectRatio(2f / 3f).background(Palette.surfaceRaised, androidx.compose.foundation.shape.RoundedCornerShape(8.dp)))
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(if (item.isEpisode) "${item.seriesName} · ${item.episodeLabel ?: item.name}" else item.name,
                        style = MaterialTheme.typography.titleLarge, maxLines = 2)
                    item.overview?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.textSecondary, maxLines = 4,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
                }
            }
            note?.let { Text(it, color = Palette.accent, style = MaterialTheme.typography.labelMedium) }
            when (val p = page) {
                Page.Menu -> Menu(state, item) { action ->
                    when (action) {
                        "play" -> { close(false); state.push(Screen.Player(item.id, null)) }
                        "restart" -> { close(false); state.push(Screen.Player(item.id, 0.0)) }
                        "details" -> { close(false); state.push(Screen.Detail(item.id)) }
                        "show" -> { close(false); state.push(Screen.Detail(item.seriesId!!)) }
                        "season" -> { close(false); state.push(Screen.Detail(item.seasonId!!)) }
                        "uptohere" -> act("Marked watched up to here.") {
                            val eps = server.episodes(userId, item.seriesId!!, null)
                            val at = eps.indexOfFirst { it.id == item.id }
                            eps.take(at + 1).filter { !it.played }.forEach { runCatching { server.setPlayed(it.id, true) } }
                        }
                        "watched" -> act(if (item.played) "Marked unwatched." else "Marked watched.") {
                            val to = !item.played
                            server.setPlayed(item.id, to)
                            state.justWatched = if (to) state.justWatched + item.id else state.justWatched - item.id
                            // Five seconds to take it back, as Apple TV offers.
                            state.undo = (if (to) "Marked watched" else "Marked unwatched") to {
                                scope.launch { runCatching { server.setPlayed(item.id, !to) }
                                    state.justWatched = state.justWatched - item.id; state.homeRefresh++ }
                            }
                        }
                        "favourite" -> act(if (item.favorite) "Removed from Favourites." else "Added to Favourites.") { server.setFavorite(item.id, !item.favorite) }
                        "hide" -> act("Off Continue Watching.") { server.hideFromContinueWatching(item.id) }
                        "watchlist" -> act(if (item.id in state.settings.watchlist) "Off Up Next." else "Added to Up Next.") {
                            val w = state.settings.watchlist
                            state.settings.watchlist = if (item.id in w) w - item.id else listOf(item.id) + w
                        }
                        "notinterested" -> act("You won't see it on Home.") { state.settings.notInterested = state.settings.notInterested + item.id }
                        "playlist" -> page = Page.Playlist
                        "collection" -> page = Page.Collection
                        "download" -> act("Downloading — see Downloads.") {
                            state.downloads.start(server, userId, server.itemJson(userId, item.id), state.settings.downloadsWifiOnly)
                        }
                        "edit" -> { close(false); state.push(Screen.Edit(item.id)) }
                        "identify" -> page = Page.Identify
                        "refresh" -> act("Refreshing — new details arrive in a moment.") { server.refreshMetadata(item.id, false) }
                        "replace" -> page = Page.Confirm("Replace metadata and artwork?", "Everything is fetched again; corrections made by hand are lost.",
                            "Replace") { server.refreshMetadata(item.id, true) }
                        "artwork" -> page = Page.Artwork
                        "frame" -> act("A frame from the file is being taken.") { server.useFrameFromFile(item.id) }
                        "remove" -> page = Page.Confirm("Remove from the library?", "The file stays on the disk. Restore it from Removed Items on the Mac.",
                            "Remove") { server.removeFromLibrary(item.id) }
                        "delete" -> page = Page.Confirm("Move the file to the Trash?", "It leaves the library and goes to the Mac's Trash.",
                            "Move to Trash") { server.deleteFile(item.id) }
                        "deletecollection" -> page = Page.Confirm("Delete this collection?", "Its films and shows stay in the library.",
                            "Delete") { server.removeFromLibrary(item.id) }
                    }
                }
                Page.Playlist -> Picker(state, "Add to Playlist", { server.playlists(userId) }, newLabel = "New Playlist",
                    onPick = { pl -> act("Added to ${pl.name}.") { server.addToPlaylist(pl.id, listOf(item.id)) } },
                    onNew = { name -> act("Added to $name.") { server.newPlaylist(name, listOf(item.id), userId) } })
                Page.Collection -> Picker(state, "Add to Collection", { server.collections(userId) }, newLabel = "New Collection",
                    onPick = { c -> act("Added to ${c.name}.") { server.addToCollection(c.id, listOf(item.id)) } },
                    onNew = { name -> act("Added to $name.") { server.newCollection(name, listOf(item.id)) } })
                Page.Identify -> Identify(state, item) { c -> act("Identified as ${c.name}.") { server.identifyApply(item.id, c) } }
                Page.Artwork -> ArtworkPicker(state, item,
                    onPick = { type, a -> act("Artwork applied.") { server.applyArtwork(item.id, type, a.url) } },
                    onRemove = { type -> act("Artwork removed.") { server.removeArtwork(item.id, type) } })
                is Page.Confirm -> Confirm(p, onNo = { page = Page.Menu }) { act("Done.") { p.run() } }
            }
        }
    }
}

@Composable
private fun Menu(state: AppState, item: Item, pick: (String) -> Unit) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    val video = item.isPlayable
    val rows = buildList {
        if (video || item.isSeries) add("play" to if (item.positionTicks > 0) "Resume" else "Play")
        if (video && item.positionTicks > 0) add("restart" to "Play from Beginning")
        add("details" to "Details")
        if (item.isEpisode && item.seriesId != null) add("show" to "Go to ${item.seriesName ?: "Show"}")
        if (item.isEpisode && item.seasonId != null) add("season" to "Go to Season")
        add("—" to "")
        add("watched" to if (item.played) "Mark as Unwatched" else "Mark as Watched")
        if (item.isEpisode && item.seriesId != null) add("uptohere" to "Mark as Watched up to Here")
        add("favourite" to if (item.favorite) "Remove from Favourites" else "Add to Favourites")
        if (!state.roomOpen && (video || item.isSeries) && item.positionTicks == 0L)
            add("watchlist" to if (item.id in state.settings.watchlist) "Remove from Up Next" else "Add to Up Next")
        add("notinterested" to "Not Interested")
        if (item.positionTicks > 0) add("hide" to "Hide from Continue Watching")
        add("playlist" to "Add to Playlist…")
        if (item.type != "BoxSet") add("collection" to "Add to Collection…")
        if (video && state.downloads.find(item.id) == null) add("download" to "Download")
        add("—" to "")
        add("edit" to "Edit Metadata…")
        if (item.type in setOf("Movie", "Series")) add("identify" to "Identify…")
        add("refresh" to "Refresh Metadata")
        add("replace" to "Replace Metadata and Artwork…")
        add("artwork" to "Choose or Remove Artwork…")
        if (video) add("frame" to "Use Frame from File as Picture")
        add("—" to "")
        if (item.type == "BoxSet") add("deletecollection" to "Delete Collection…")
        else add("remove" to "Remove from Library…")
        if (video) add("delete" to "Delete File…")
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        var firstSet = false
        rows.forEach { (key, label) ->
            if (key == "—") item { Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).background(Color.White.copy(alpha = 0.1f)).padding(0.5.dp)) }
            else {
                val isFirst = !firstSet.also { firstSet = true }
                item(key = key) {
                    app.lumiere.android.ui.TvPill({ pick(key) },
                        Modifier.fillMaxWidth().then(if (isFirst) Modifier.focusRequester(first) else Modifier),
                        tint = if (key in setOf("remove", "delete", "deletecollection")) Color(0xFFE57373) else Palette.textPrimary) {
                        Text(label, style = MaterialTheme.typography.titleMedium)
                    }
                }
            }
        }
    }
}

@Composable
private fun Picker(state: AppState, title: String, load: suspend () -> List<Item>, newLabel: String,
                   onPick: (Item) -> Unit, onNew: (String) -> Unit) {
    var list by remember { mutableStateOf<List<Item>?>(null) }
    var name by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { list = runCatching { state.visible(load()) }.getOrDefault(emptyList()) }
    Text(title, style = MaterialTheme.typography.titleMedium, color = Palette.accent)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text(newLabel) }, modifier = Modifier.weight(1f))
        LButton(enabled = name.isNotBlank(), onClick = { onNew(name.trim()) }) { Text("Add") }
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items(list.orEmpty(), key = { it.id }) { it ->
            Text(it.name, style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.fillMaxWidth().focusCard { onPick(it) }.padding(horizontal = 12.dp, vertical = 10.dp))
        }
    }
}

@Composable
private fun Identify(state: AppState, item: Item, onPick: (Candidate) -> Unit) {
    val server = state.server ?: return
    var name by remember { mutableStateOf(item.name) }
    var year by remember { mutableStateOf(item.year?.toString() ?: "") }
    var results by remember { mutableStateOf<List<Candidate>?>(null) }
    val scope = rememberCoroutineScope()
    fun search() = scope.launch { results = runCatching { server.identifySearch(name, year.toIntOrNull(), item.isSeries) }.getOrDefault(emptyList()) }
    LaunchedEffect(Unit) { search() }
    // A text field keeps the D-pad for its cursor, so the remote moves out of
    // it by hand; and it lands somewhere at once — the first match, or Search.
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val firstResult = remember { FocusRequester() }
    val searchButton = remember { FocusRequester() }
    LaunchedEffect(results) {
        kotlinx.coroutines.delay(80)
        runCatching { if (results.isNullOrEmpty()) searchButton.requestFocus() else firstResult.requestFocus() }
    }
    val leave = Modifier.onPreviewKeyEvent { e ->
        if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
        when (e.nativeKeyEvent.keyCode) {
            android.view.KeyEvent.KEYCODE_DPAD_DOWN -> focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Down)
            android.view.KeyEvent.KEYCODE_DPAD_UP -> focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Up)
            android.view.KeyEvent.KEYCODE_DPAD_RIGHT -> focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Right)
            else -> false
        }
    }
    Text("Identify", style = MaterialTheme.typography.titleMedium, color = Palette.accent)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(name, { name = it }, singleLine = true, modifier = Modifier.weight(1f).then(leave),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onAny = { search() }))
        OutlinedTextField(year, { year = it.filter(Char::isDigit).take(4) }, singleLine = true, modifier = Modifier.width(90.dp).then(leave),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onAny = { search() }))
        LButton(onClick = { search() }, modifier = Modifier.focusRequester(searchButton)) { Text("Search") }
    }
    if (results?.isEmpty() == true) Text("Nothing found. Check the name, or the server's movie database key.", style = MaterialTheme.typography.labelMedium)
    LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        itemsIndexed(results.orEmpty()) { i, c ->
            app.lumiere.android.ui.TvPill({ onPick(c) }, Modifier.fillMaxWidth().then(if (i == 0) Modifier.focusRequester(firstResult) else Modifier),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                c.image?.let { AsyncImage(it, null, contentScale = ContentScale.Crop, modifier = Modifier.width(50.dp).aspectRatio(2f / 3f)) }
                Column {
                    Text(listOfNotNull(c.name, c.year?.toString()).joinToString(" · "), style = MaterialTheme.typography.titleMedium)
                    c.overview?.let { Text(it, style = MaterialTheme.typography.labelMedium, maxLines = 2) }
                }
            }
            }
        }
    }
}

@Composable
private fun ArtworkPicker(state: AppState, item: Item, onPick: (String, Artwork) -> Unit, onRemove: (String) -> Unit) {
    val server = state.server ?: return
    var type by remember { mutableStateOf("Primary") }
    var art by remember(type) { mutableStateOf<List<Artwork>?>(null) }
    LaunchedEffect(type) { art = server.remoteArtwork(item.id, type) }
    Text("Choose or Remove Artwork", style = MaterialTheme.typography.titleMedium, color = Palette.accent)
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(listOf("Primary" to "Poster", "Backdrop" to "Backdrop", "Logo" to "Logo", "Thumb" to "Thumbnail")) { (t, l) ->
            LChip(type == t, { type = t }, { Text(l) })
        }
    }
    LButton(primary = false, onClick = { onRemove(type) }) { Text("Remove the current one") }
    if (art?.isEmpty() == true) Text("No artwork offered for this.", style = MaterialTheme.typography.labelMedium)
    LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(art.orEmpty(), key = { it.url }) { a ->
            Box(Modifier.width(if (type == "Primary") 110.dp else 200.dp)
                .aspectRatio(if (type == "Primary") 2f / 3f else 16f / 9f).focusCard { onPick(type, a) }.background(Palette.surfaceRaised)) {
                AsyncImage(a.url, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
            }
        }
    }
}

@Composable
private fun Confirm(p: Page.Confirm, onNo: () -> Unit, onYes: () -> Unit) {
    val no = remember { FocusRequester() }
    LaunchedEffect(p) { runCatching { no.requestFocus() } }
    Text(p.title, style = MaterialTheme.typography.titleLarge)
    Text(p.note, style = MaterialTheme.typography.bodyMedium)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        LButton(primary = false, onClick = onYes) { Text(p.label) }
        // Cancel has focus: the safe answer is the one a stray press gives.
        LButton(modifier = Modifier.focusRequester(no), onClick = onNo) { Text("Cancel") }
    }
}
