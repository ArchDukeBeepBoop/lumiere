@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.ui

import app.lumiere.android.cache.childrenOrSaved
import app.lumiere.android.cache.episodesOrSaved
import app.lumiere.android.cache.itemOrSaved
import app.lumiere.android.cache.seasonsOrSaved

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import coil.compose.AsyncImage
import app.lumiere.android.api.itemJson
import app.lumiere.android.api.extras
import app.lumiere.android.api.similar
import app.lumiere.android.api.personImage
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import app.lumiere.android.api.setFavorite
import kotlinx.coroutines.launch

/**
 * One title. A film or episode gets Play and Resume; a show its seasons and
 * episodes, opening on the season with the next unwatched one; a collection
 * or folder its contents.
 */
@Composable
fun DetailScreen(state: AppState, id: String, refreshKey: Int) {
    val server = state.server ?: return
    val session = state.session ?: return
    val form = LocalFormFactor.current
    val scope = rememberCoroutineScope()
    var item by remember { mutableStateOf<Item?>(null) }
    var seasons by remember { mutableStateOf<List<Item>>(emptyList()) }
    var season by remember { mutableStateOf<Item?>(null) }
    var episodes by remember { mutableStateOf<List<Item>>(emptyList()) }
    var children by remember { mutableStateOf<List<Item>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var similar by remember { mutableStateOf<List<Item>>(emptyList()) }
    var extras by remember { mutableStateOf<List<Item>>(emptyList()) }

    LaunchedEffect(id, refreshKey) {
        runCatching { state.itemOrSaved(id) }
            .onSuccess { found ->
                item = found
                when {
                    found.isSeries -> {
                        seasons = state.seasonsOrSaved(id)
                        season = season?.let { s -> seasons.firstOrNull { it.id == s.id } }
                            ?: seasons.firstOrNull { (it.unplayedCount ?: 0) > 0 } ?: seasons.firstOrNull()
                    }
                    found.isFolder -> children = state.childrenOrSaved(id)
                }
            }
            .onFailure { error = it.message }
        similar = state.visible(runCatching { server.similar(session.userId, id) }.getOrDefault(emptyList()))
        extras = server.extras(session.userId, id)
    }
    LaunchedEffect(season?.id, refreshKey) {
        val s = season ?: return@LaunchedEffect
        episodes = runCatching { state.episodesOrSaved(id, s.id) }.getOrDefault(emptyList())
    }

    val current = item
    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        if (current == null) {
            if (error != null) Text(error!!, Modifier.align(Alignment.Center).padding(24.dp))
            else CircularProgressIndicator(Modifier.align(Alignment.Center))
            return@Box
        }
        val list = androidx.compose.foundation.lazy.rememberLazyListState()
        LazyColumn(state = list, contentPadding = PaddingValues(bottom = 40.dp)) {
            item { Hero(current, state, if (form.isTv) Modifier else Modifier.collapsing(list)) }
            item {
                Column(Modifier.padding(horizontal = form.gutter.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (current.isPlayable) PlayButtons(current, state, onPlayed = { played ->
                        scope.launch { server.setPlayed(current.id, played); item = current.copy(played = played) }
                    })
                    TitleActions(current, state, onFavorite = { fav ->
                        scope.launch { server.setFavorite(current.id, fav); item = current.copy(favorite = fav) }
                    })
                    current.overview?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                }
            }
            if (current.isSeries && seasons.isNotEmpty()) {
                // On a phone the season tabs stay at the top while its episodes scroll.
                if (form.isTv) item { SeasonTabs(seasons, season) { season = it } }
                else {
                    stickyHeader(key = "seasons") {
                        val stuck by remember { androidx.compose.runtime.derivedStateOf { list.firstVisibleItemIndex >= 2 } }
                        SeasonTabs(seasons, season, if (stuck) current.name else null) { season = it }
                    }
                    item(key = "download-season") { DownloadSeason(season, episodes, state) }
                }
                items(episodes, key = { it.id }) { episode ->
                    if (form.isTv) EpisodeRow(episode, state)
                    else PhoneEpisodeRow(episode, state) { played ->
                        scope.launch {
                            server.setPlayed(episode.id, played)
                            episodes = episodes.map { if (it.id == episode.id) it.copy(played = played) else it }
                        }
                    }
                }
            }
            if (children.isNotEmpty()) {
                item { Shelf("Contents", children, server, CardShape.Poster) { state.push(Screen.Detail(it.id)) } }
            }
            if (current.people.isNotEmpty()) item { CastRow(current, state) }
            if (extras.isNotEmpty()) item {
                Shelf("Extras", extras, server, CardShape.Wide) { state.push(Screen.Player(it.id, 0.0)) }
            }
            if (similar.isNotEmpty()) item {
                Shelf("More Like This", similar, server, CardShape.Poster) { state.push(Screen.Detail(it.id)) }
            }
        }
        // A show's title rides in its sticky season tabs instead.
        if (!form.isTv && !(current.isSeries && seasons.isNotEmpty())) CollapsedTitle(current, list)
    }
}

@Composable
private fun Hero(item: Item, state: AppState, modifier: Modifier = Modifier) {
    val server = state.server ?: return
    val form = LocalFormFactor.current
    val art = imageFor(item, server, CardShape.Wide, 1280)
    Box(modifier.fillMaxWidth().aspectRatio(if (form.isTv) 3.2f else 16f / 9f)) {
        AsyncImage(art, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Palette.canvas))))
        Column(Modifier.align(Alignment.BottomStart).padding(horizontal = form.gutter.dp, vertical = 12.dp)) {
            item.seriesName?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = Palette.accent) }
            if (item.logoTag != null && !item.isEpisode) {
                AsyncImage(server.imageUrl(item.id, "Logo", item.logoTag, 600), item.name,
                    contentScale = ContentScale.Fit, alignment = Alignment.BottomStart,
                    modifier = Modifier.height(if (form.isTv) 100.dp else 64.dp).fillMaxWidth(0.6f))
            } else {
                Text(item.name, style = MaterialTheme.typography.headlineLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val facts = listOfNotNull(
                item.episodeLabel, item.year?.toString(), item.officialRating,
                item.runtimeTicks?.let { "${it / TICKS_PER_SECOND / 60} min" },
                item.genres.take(3).joinToString(", ").ifEmpty { null },
            )
            Text(facts.joinToString("  ·  "), style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun PlayButtons(item: Item, state: AppState, onPlayed: (Boolean) -> Unit) {
    // A row that scrolls rather than squeezing: three buttons do not fit a phone's width.
    androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically) { item {
      Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (item.positionTicks > 0) {
            val minutes = item.positionTicks / TICKS_PER_SECOND / 60
            LButton(onClick = { state.push(Screen.Player(item.id, null)) }) { Text("Resume from $minutes min") }
            LButton(primary = false, onClick = { state.push(Screen.Player(item.id, 0.0)) }) { Text("Start Over") }
        } else {
            LButton(onClick = { state.push(Screen.Player(item.id, 0.0)) }) { Text("Play") }
        }
        LButton(primary = false, onClick = { onPlayed(!item.played) }) {
            Text(if (item.played) "Mark Unwatched" else "Mark Watched")
        }
      }
    } }
}

@Composable
private fun EpisodeRow(episode: Item, state: AppState) {
    val server = state.server ?: return
    val form = LocalFormFactor.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.width(if (form.isTv) 240.dp else 150.dp)) {
            ItemCardImage(episode, server) { state.push(Screen.Player(episode.id, null)) }
        }
        Column(Modifier.weight(1f)) {
            Text(listOfNotNull(episode.indexNumber?.let { "$it." }, episode.name).joinToString(" "),
                style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            episode.runtimeTicks?.let {
                Text("${it / TICKS_PER_SECOND / 60} min" + if (episode.played) "  ·  Watched" else "",
                    style = MaterialTheme.typography.labelMedium)
            }
            episode.overview?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Just the picture of a wide card, for rows that set their own text. */
@Composable
fun ItemCardImage(item: Item, server: app.lumiere.android.api.Server, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).focusCard(onClick).background(Palette.surface)) {
        AsyncImage(imageFor(item, server, CardShape.Wide, 480), item.name,
            contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        item.progress?.let { fraction ->
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(fraction).padding(top = 0.dp)
                .aspectRatio(100f).background(Palette.accent))
        }
    }
}

/** Favourite, Download (films and episodes), and Edit. */
@Composable
private fun TitleActions(item: Item, state: AppState, onFavorite: (Boolean) -> Unit) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val scope = rememberCoroutineScope()
    val saved = state.downloads.find(item.id)
    androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            LButton(primary = false, onClick = { onFavorite(!item.favorite) }) {
                Text(if (item.favorite) "★ Favourite" else "☆ Favourite")
            }
        }
        if (item.isPlayable) item {
            LButton(primary = false, onClick = {
                if (saved != null) state.push(Screen.Downloads)
                else scope.launch {
                    runCatching { server.itemJson(userId, item.id) }.onSuccess {
                        state.downloads.start(server, userId, it, state.settings.downloadsWifiOnly)
                    }
                }
            }) { Text(if (saved != null) "Downloaded" else "Download") }
        }
        item { LButton(primary = false, onClick = { state.push(Screen.Edit(item.id)) }) { Text("Edit") } }
    }
}

/** The cast, as round portraits with their part; a press lists everything they are in. */
@Composable
private fun CastRow(item: Item, state: AppState) {
    val server = state.server ?: return
    val form = LocalFormFactor.current
    Column(Modifier.padding(vertical = 10.dp)) {
        Text("Cast & Crew", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = form.gutter.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(item.people.take(30), key = { it.id + (it.role ?: "") }) { p ->
                Column(Modifier.width(92.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(78.dp).clip(CircleShape).focusCard { state.push(Screen.Person(p.id, p.name)) }
                        .background(Palette.surface), contentAlignment = Alignment.Center) {
                        Text(p.name.split(' ').mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString(""),
                            style = MaterialTheme.typography.titleMedium)
                        if (p.imageTag != null) AsyncImage(server.personImage(p.id, p.imageTag), p.name,
                            contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                    }
                    Text(p.name, style = MaterialTheme.typography.labelMedium, color = Palette.textPrimary,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    (p.role ?: p.type)?.let { Text(it, style = MaterialTheme.typography.labelMedium, maxLines = 1,
                        overflow = TextOverflow.Ellipsis) }
                }
            }
        }
    }
}
