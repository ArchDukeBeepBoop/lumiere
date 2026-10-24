package app.lumiere.android.local

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.IosButton
import app.lumiere.android.ui.IosCaption
import app.lumiere.android.ui.IosChip
import app.lumiere.android.ui.IosCircle
import app.lumiere.android.ui.IosSegmented
import app.lumiere.android.ui.IosTintedButton
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.iosClick
import app.lumiere.android.ui.phoneColumns

/**
 * On This Phone, as a library: the phone's own videos by folder with their
 * frames and lengths, and its music by album, artist or song — read from
 * Android's media catalogue once allowed — played with no Mac needed. Files
 * kept elsewhere are still chosen through the picker.
 */
@Composable
fun OnThisPhoneScreen(state: AppState) {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(MediaLibrary.allowed(context)) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { allowed = MediaLibrary.allowed(context) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri?.let { val e = LocalFiles.remember(context, it); LocalQueue.items = emptyList(); state.push(Screen.LocalFile(e.uri, e.name)) }
    }
    // Kept across a song's page, so Back returns to the same tab.
    var kind by LibraryTabs.kind // videos, music
    var musicBy by LibraryTabs.musicBy // albums, artists, songs
    var open by remember { mutableStateOf<Pair<String, List<PhoneSong>>?>(null) } // an album or artist
    var videos by remember { mutableStateOf<List<PhoneVideo>?>(null) }
    var songs by remember { mutableStateOf<List<PhoneSong>?>(null) }
    LaunchedEffect(allowed) {
        LocalFiles.load(context)
        if (allowed) { videos = MediaLibrary.videos(context); songs = MediaLibrary.songs(context) }
    }
    open?.let { (title, list) -> BackHandler { open = null }; SongList(state, title, list) { open = null }; return }

    fun play(entries: List<LocalEntry>, at: Int) { LocalQueue.items = entries; state.push(Screen.LocalFile(entries[at].uri, entries[at].name)) }
    fun songEntries(list: List<PhoneSong>) = list.map { LocalEntry(it.uri, it.title, false, it.artist, it.album) }

    LazyVerticalGrid(GridCells.Fixed(phoneColumns()), Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                Text("On This Phone", style = IosType.largeTitle, color = Palette.textPrimary, modifier = Modifier.weight(1f))
                IosCircle(Icons.Default.FolderOpen, "Choose a file", { pick.launch(arrayOf("video/*", "audio/*")) }, size = 36)
            }
        }
        if (!allowed) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Default.MusicNote, null, tint = Palette.textMuted, modifier = Modifier.size(54.dp))
                    Text("Your Videos and Music", style = IosType.title, color = Palette.textPrimary)
                    Text("Allow Lumiere to see the videos and music on this phone to browse them here as a library. They stay on the phone; nothing is sent to the Mac.",
                        style = IosType.body, color = Palette.textSecondary, textAlign = TextAlign.Center)
                    IosButton("Allow Access", { ask.launch(MediaLibrary.permissions()) }, Modifier.fillMaxWidth())
                    IosButton("Choose a File Instead", { pick.launch(arrayOf("video/*", "audio/*")) }, Modifier.fillMaxWidth(), primary = false)
                }
            }
            return@LazyVerticalGrid
        }
        item(span = { GridItemSpan(maxLineSpan) }) { IosSegmented(listOf("Videos", "Music"), kind, { kind = it }, Modifier.padding(vertical = 4.dp)) }
        if (kind == 0) {
            val all = videos
            if (all == null) return@LazyVerticalGrid
            if (all.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { Empty("No videos on this phone.") }
            all.groupBy { it.folder }.entries.sortedByDescending { e -> e.value.maxOf { it.added } }.forEach { (folder, list) ->
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.padding(top = 14.dp)) {
                        Text(folder, style = IosType.title, color = Palette.textPrimary)
                        Text("${list.size} video${if (list.size == 1) "" else "s"}", style = IosType.footnote, color = Palette.textSecondary)
                    }
                }
                val entries = list.map { LocalEntry(it.uri, it.name, true) }
                itemsIndexed(list, key = { _, v -> v.uri }) { i, v -> VideoTile(v) { play(entries, i) } }
            }
        } else {
            val all = songs
            if (all == null) return@LazyVerticalGrid
            if (all.isEmpty()) { item(span = { GridItemSpan(maxLineSpan) }) { Empty("No music on this phone.") }; return@LazyVerticalGrid }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("Albums", "Artists", "Songs").forEachIndexed { i, l -> IosChip(musicBy == i, l) { musicBy = i } }
                }
            }
            when (musicBy) {
                0 -> items(all.groupBy { it.albumId }.values.sortedBy { it.first().album.lowercase() }, key = { "al" + it.first().albumId }) { album ->
                    AlbumTile(album) { open = album.first().album to album.sortedBy { it.track } }
                }
                1 -> items(all.groupBy { it.artist }.entries.sortedBy { it.key.lowercase() }.toList(), key = { "ar" + it.key },
                    span = { GridItemSpan(maxLineSpan) }) { (artist, list) ->
                    Line(artist, "${list.size} song${if (list.size == 1) "" else "s"}") { open = artist to list.sortedWith(compareBy({ it.album }, { it.track })) }
                }
                else -> {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            IosTintedButton("Play", Icons.Default.PlayArrow, { play(songEntries(all), 0) }, Modifier.weight(1f))
                            IosTintedButton("Shuffle", Icons.Default.Shuffle, { play(songEntries(all.shuffled()), 0) }, Modifier.weight(1f))
                        }
                    }
                    itemsIndexed(all, key = { _, s -> s.uri }, span = { _, _ -> GridItemSpan(maxLineSpan) }) { i, s ->
                        Line(s.title, "${s.artist} · ${s.album}") { play(songEntries(all), i) }
                    }
                }
            }
        }
        val recent = LocalFiles.recent.value
        if (recent.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Row(Modifier.padding(top = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Opened from Files", style = IosType.title, color = Palette.textPrimary, modifier = Modifier.weight(1f))
                    Text("Clear", style = IosType.body, color = Palette.accent, modifier = Modifier.clickable { LocalFiles.forget(context) })
                }
            }
            items(recent, key = { "r" + it.uri }, span = { GridItemSpan(maxLineSpan) }) { e ->
                Line(e.name, if (e.video) "Video" else "Song") { LocalQueue.items = emptyList(); state.push(Screen.LocalFile(e.uri, e.name)) }
            }
        }
    }
}

/** The tabs last chosen, kept while the page is away (the screen is rebuilt on return). */
private object LibraryTabs {
    val kind = mutableStateOf(0)
    val musicBy = mutableStateOf(0)
}

@Composable
private fun Empty(text: String) = Text(text, style = IosType.body, color = Palette.textSecondary,
    modifier = Modifier.fillMaxWidth().padding(40.dp), textAlign = TextAlign.Center)

@Composable
private fun Thumb(uri: String?, modifier: Modifier, fallback: @Composable () -> Unit) {
    val context = LocalContext.current
    val bmp by produceState<Bitmap?>(null, uri) { value = uri?.let { MediaLibrary.thumbnail(context, it) } }
    Box(modifier.background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
        bmp?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) } ?: fallback()
    }
}

/** A video: its frame, its length in the corner, its name. */
@Composable
private fun VideoTile(v: PhoneVideo, onClick: () -> Unit) {
    Column(Modifier.iosClick(onClick)) {
        Box {
            Thumb(v.uri, Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(8.dp))) {}
            Text(app.lumiere.android.music.clock(v.durationMs / 1000.0), style = IosType.caption, color = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(5.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 1.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(v.name.substringBeforeLast('.'), style = IosType.footnote, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun AlbumTile(album: List<PhoneSong>, onClick: () -> Unit) {
    val first = album.first()
    Column(Modifier.iosClick(onClick)) {
        Thumb(first.uri, Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(8.dp))) {
            Icon(Icons.Default.MusicNote, null, tint = Palette.textMuted, modifier = Modifier.size(36.dp))
        }
        Spacer(Modifier.height(4.dp))
        Text(first.album, style = IosType.footnote, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(first.artist, style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Line(title: String, sub: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(Modifier.padding(vertical = 9.dp)) {
            Text(title, style = IosType.body, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(sub, style = IosType.footnote, color = Palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        HorizontalDivider(thickness = 0.5.dp, color = Palette.border)
    }
}

/** An album's or artist's songs, with Play and Shuffle. */
@Composable
private fun SongList(state: AppState, title: String, songs: List<PhoneSong>, onBack: () -> Unit) {
    val entries = songs.map { LocalEntry(it.uri, it.title, false, it.artist, it.album) }
    fun play(list: List<LocalEntry>, at: Int) { LocalQueue.items = list; state.push(Screen.LocalFile(list[at].uri, list[at].name)) }
    androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp)) {
        item {
            Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth()) { IosCircle(Icons.AutoMirrored.Filled.ArrowBack, "Back", onBack, size = 34) }
                Thumb(songs.firstOrNull()?.uri, Modifier.width(220.dp).aspectRatio(1f).clip(RoundedCornerShape(10.dp))) {
                    Icon(Icons.Default.MusicNote, null, tint = Palette.textMuted, modifier = Modifier.size(54.dp))
                }
                Text(title, style = IosType.title, color = Palette.textPrimary, textAlign = TextAlign.Center)
                IosCaption("${songs.size} song${if (songs.size == 1) "" else "s"}")
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(vertical = 6.dp)) {
                    IosTintedButton("Play", Icons.Default.PlayArrow, { play(entries, 0) }, Modifier.weight(1f))
                    IosTintedButton("Shuffle", Icons.Default.Shuffle, { play(entries.shuffled(), 0) }, Modifier.weight(1f))
                }
            }
        }
        items(songs.size) { i -> Line(songs[i].title, songs[i].artist) { play(entries, i) } }
    }
}
