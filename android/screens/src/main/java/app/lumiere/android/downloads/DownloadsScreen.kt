package app.lumiere.android.downloads

import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.aspectRatio
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import android.app.DownloadManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette
import kotlinx.coroutines.delay

/** What is saved on the phone, what is still arriving, and room to take it off. */
@Composable
fun DownloadsScreen(state: AppState) {
    val form = LocalFormFactor.current
    val downloads = state.downloads
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(1000); tick++ } }
    val shown = downloads.all.filter { !state.hides(it.item.libraryId) }
    Column(Modifier.fillMaxSize().background(Palette.canvas)) {
        Text("Downloads", style = MaterialTheme.typography.headlineLarge, modifier = Modifier.padding(form.gutter.dp))
        if (downloads.all.isNotEmpty()) {
            tick.let { }
            val used = downloads.usedBytes() / 1e9
            val cap = state.settings.downloadCapGb
            Text(if (cap > 0) "%.1f GB of %d GB used".format(used, cap) else "%.1f GB used".format(used),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(start = form.gutter.dp, end = form.gutter.dp, bottom = 8.dp))
            if (cap > 0) LinearProgressIndicator(progress = { (used / cap).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp))
        }
        if (shown.isEmpty()) {
            Text("Nothing saved yet. Open a film or episode and choose Download to watch it with no server in reach.",
                style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(horizontal = form.gutter.dp))
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 96.dp)) {
            items(shown, key = { it.id }) { d ->
                tick.let { }
                val status = downloads.status(d)
                Row(Modifier.fillMaxWidth().padding(horizontal = form.gutter.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    // The title's picture beside it, with a ring while it is still arriving.
                    state.server?.let { srv -> Box(contentAlignment = Alignment.Center) {
                        coil.compose.AsyncImage(app.lumiere.android.ui.imageFor(d.item, srv, app.lumiere.android.ui.CardShape.Wide, 240), null,
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                            modifier = Modifier.width(if (form.isTv) 160.dp else 112.dp).aspectRatio(16f / 9f)
                                .background(Palette.surface, androidx.compose.foundation.shape.RoundedCornerShape(8.dp)))
                        if (status == DownloadManager.STATUS_RUNNING) androidx.compose.material3.CircularProgressIndicator(
                            progress = { downloads.progress(d) }, color = Palette.accent, strokeWidth = 3.dp, modifier = Modifier.size(36.dp))
                    } }
                    Column(Modifier.weight(1f)) {
                        Text(d.item.seriesName ?: d.item.name, style = MaterialTheme.typography.titleMedium)
                        if (d.item.seriesName != null) {
                            Text(listOfNotNull(d.item.episodeLabel, d.item.name).joinToString(" · "),
                                style = MaterialTheme.typography.labelMedium)
                        }
                        when (status) {
                            DownloadManager.STATUS_SUCCESSFUL -> Text("%.1f GB".format(d.file.length() / 1e9),
                                style = MaterialTheme.typography.labelMedium)
                            DownloadManager.STATUS_FAILED -> Text("Failed — remove it and try again",
                                style = MaterialTheme.typography.labelMedium, color = Palette.accent)
                            DownloadManager.STATUS_PAUSED, DownloadManager.STATUS_PENDING ->
                                Text("Waiting for Wi-Fi or the server", style = MaterialTheme.typography.labelMedium)
                            else -> Box(Modifier.width(200.dp).padding(top = 6.dp)) {
                                LinearProgressIndicator(progress = { downloads.progress(d) })
                            }
                        }
                    }
                    if (status == DownloadManager.STATUS_SUCCESSFUL) {
                        LTextButton(onClick = { state.push(Screen.Player(d.id, null)) }) { Text("Play") }
                    }
                    LTextButton(onClick = { downloads.remove(d.id) }) { Text("Remove") }
                }
            }
        }
    }
}
