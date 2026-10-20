@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.lumiere.android.downloads

import android.app.DownloadManager
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.CardShape
import app.lumiere.android.ui.IosCaption
import app.lumiere.android.ui.IosCollapsedTitle
import app.lumiere.android.ui.IosLargeTitle
import app.lumiere.android.ui.IosType
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.episodeShort
import app.lumiere.android.ui.imageFor
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * Downloads on a phone, as the Apple TV app's Downloaded page: the space
 * Lumiere takes against the rest of the phone, in iPhone Storage's bar; what
 * is still arriving; then films, and each show with its episodes. Tap to
 * play with no connection, swipe left to delete.
 */
@Composable
fun PhoneDownloads(state: AppState) {
    val downloads = state.downloads
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(1000); tick++ } }
    tick.let { }
    val shown = downloads.all.filter { !state.hides(it.item.libraryId) }
    val arriving = shown.filter { downloads.status(it) != DownloadManager.STATUS_SUCCESSFUL }
    val done = shown - arriving.toSet()
    val films = done.filter { it.item.seriesName == null }
    val shows = done.filter { it.item.seriesName != null }.groupBy { it.item.seriesName!! }
    val list = androidx.compose.foundation.lazy.rememberLazyListState()

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 96.dp)) {
            item { IosLargeTitle("Downloads") }
            item { Storage(state) }
            if (shown.isEmpty()) item { Empty() }
            if (arriving.isNotEmpty()) {
                item { Header("Downloading") }
                items(arriving, key = { "a" + it.id }) { d -> Swipe(state, d) { DownloadRow(state, d, wide = true) } }
            }
            if (films.isNotEmpty()) {
                item { Header("Movies") }
                items(films, key = { it.id }) { d -> Swipe(state, d) { DownloadRow(state, d, wide = false) } }
            }
            shows.toSortedMap().forEach { (show, episodes) ->
                item(key = "show-$show") {
                    Header(show, "${episodes.size} episode${if (episodes.size == 1) "" else "s"} · " +
                        size(episodes.sumOf { it.file.length() }))
                }
                items(episodes.sortedWith(compareBy({ it.item.parentIndexNumber ?: 0 }, { it.item.indexNumber ?: 0 })), key = { it.id }) { d ->
                    Swipe(state, d) { DownloadRow(state, d, wide = true) }
                }
            }
        }
        IosCollapsedTitle(list, "Downloads")
    }
}

/** iPhone Storage's bar: Lumiere, the rest of the phone, what is free; the limit Settings sets beneath. */
@Composable
private fun Storage(state: AppState) {
    val context = LocalContext.current
    val stat = remember { runCatching { android.os.StatFs((context.getExternalFilesDir(null) ?: context.filesDir).path) }.getOrNull() }
    val total = stat?.totalBytes ?: 0L
    val free = stat?.availableBytes ?: 0L
    val ours = state.downloads.usedBytes()
    val other = (total - free - ours).coerceAtLeast(0L)
    val cap = state.settings.downloadCapGb
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).clip(RoundedCornerShape(12.dp))
        .background(Palette.surface).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("Phone Storage", style = IosType.headline, color = Palette.textPrimary, modifier = Modifier.weight(1f))
            if (total > 0) Text("${size(total - free)} of ${size(total)} used", style = IosType.footnote, color = Palette.textSecondary)
        }
        if (total > 0) Row(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(3.dp)).background(Palette.surfaceRaised)) {
            Box(Modifier.weight((ours.toFloat() / total).coerceAtLeast(0.006f)).fillMaxHeight().background(Palette.accent))
            Box(Modifier.width(1.dp).fillMaxHeight().background(Palette.surface))
            Box(Modifier.weight((other.toFloat() / total).coerceAtLeast(0.001f)).fillMaxHeight().background(Color(0xFF8E8E93)))
            Box(Modifier.weight((free.toFloat() / total).coerceAtLeast(0.001f)).fillMaxHeight())
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Legend(Palette.accent, "Lumiere ${size(ours)}")
            Legend(Color(0xFF8E8E93), "Other")
            Legend(Palette.surfaceRaised, "Free ${size(free)}")
        }
        if (cap > 0) Text("Downloads may use up to $cap GB — Settings › Space downloads may use.", style = IosType.footnote,
            color = Palette.textSecondary)
    }
}

@Composable
private fun Legend(colour: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(colour))
        Spacer(Modifier.width(5.dp))
        Text(text, style = IosType.footnote, color = Palette.textSecondary)
    }
}

@Composable
private fun Header(title: String, subtitle: String? = null) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 6.dp)) {
        Text(title, style = IosType.title, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        subtitle?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary) }
    }
}

@Composable
private fun Empty() {
    Column(Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 60.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Default.Download, null, tint = Palette.textMuted, modifier = Modifier.size(54.dp))
        Text("No Downloads", style = IosType.title, color = Palette.textPrimary)
        Text("Download films and episodes from their pages to watch them with no connection to the Mac.",
            style = IosType.body, color = Palette.textSecondary, textAlign = TextAlign.Center)
    }
}

/** iOS's swipe left to delete, red beneath. */
@Composable
private fun Swipe(state: AppState, d: Download, content: @Composable () -> Unit) {
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = {
        if (it == SwipeToDismissBoxValue.EndToStart) { state.downloads.remove(d.id); true } else false
    })
    SwipeToDismissBox(swipe, enableDismissFromStartToEnd = false, backgroundContent = {
        Box(Modifier.fillMaxSize().background(Color(0xFFFF453A)).padding(end = 22.dp), contentAlignment = Alignment.CenterEnd) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Default.Delete, null, tint = Color.White)
                Text("Delete", style = IosType.headline, color = Color.White)
            }
        }
    }) { Box(Modifier.background(Palette.canvas)) { content() } }
}

/** A download as an iOS row: poster or still, its name, what it is, its size or progress. */
@Composable
private fun DownloadRow(state: AppState, d: Download, wide: Boolean) {
    val server = state.server
    val status = state.downloads.status(d)
    val ready = status == DownloadManager.STATUS_SUCCESSFUL
    Column(Modifier.fillMaxWidth().combinedClickable(onClick = { if (ready) state.push(Screen.Player(d.id, null)) })
        .padding(start = 16.dp)) {
        androidx.compose.foundation.layout.Row(Modifier.padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(if (wide) 112.dp else 58.dp).aspectRatio(if (wide) 16f / 9f else 2f / 3f).clip(RoundedCornerShape(7.dp))
                .background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
                if (server != null) AsyncImage(imageFor(d.item, server, if (wide) CardShape.Wide else CardShape.Poster, 300), null,
                    contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
                if (status == DownloadManager.STATUS_RUNNING) {
                    Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.45f)))
                    CircularProgressIndicator(progress = { state.downloads.progress(d) }, color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.25f), strokeWidth = 3.dp, modifier = Modifier.size(30.dp))
                }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f).padding(end = 16.dp)) {
                if (d.item.seriesName != null) IosCaption(listOfNotNull(episodeShort(d.item), d.item.seriesName).joinToString(" · "))
                Text(d.item.name, style = IosType.headline, color = Palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> listOfNotNull(d.item.year?.takeIf { d.item.seriesName == null }?.toString(),
                        size(d.file.length())).joinToString(" · ")
                    DownloadManager.STATUS_FAILED -> "Didn't finish — swipe left to delete, then download again"
                    DownloadManager.STATUS_PAUSED, DownloadManager.STATUS_PENDING -> "Waiting for Wi-Fi or the Mac"
                    else -> "Downloading · ${(state.downloads.progress(d) * 100).toInt()}%"
                }, style = IosType.footnote, color = if (status == DownloadManager.STATUS_FAILED) Color(0xFFFF453A) else Palette.textSecondary)
            }
        }
        HorizontalDivider(Modifier.padding(start = if (wide) 124.dp else 70.dp), thickness = 0.5.dp, color = Palette.border)
    }
}

/** "1.4 GB", "820 MB". */
private fun size(bytes: Long): String = if (bytes >= 1_000_000_000L) "%.1f GB".format(bytes / 1e9) else "${bytes / 1_000_000} MB"
