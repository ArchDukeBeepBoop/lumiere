package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.Palette
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Home when the Mac does not answer: what is downloaded plays anyway, a
 * wake-up is sent if the Mac's address is known, and Home tries again every
 * ten seconds by itself.
 */
@Composable
fun OfflineHome(state: AppState, reason: String, retry: () -> Unit) {
    val scope = rememberCoroutineScope()
    val wake = state.settings.wakeAddress
    var note by remember { mutableStateOf(if (wake.isNotEmpty()) "Waking the Mac…" else reason) }
    LaunchedEffect(Unit) {
        if (wake.isNotEmpty()) Wake.send(wake)
        while (true) { delay(10_000); retry() }
    }
    val saved = state.downloads.all.filter { !state.hides(it.item.libraryId) && state.downloads.playable(it.id) != null }
    Column(Modifier.fillMaxSize().background(Palette.canvas).padding(56.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Can't reach the Mac", style = MaterialTheme.typography.headlineLarge)
        Text(note, style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LButton(onClick = retry) { Text("Try Again") }
            if (wake.isNotEmpty()) LButton(primary = false, onClick = {
                scope.launch { note = if (Wake.send(wake)) "Wake-up sent. The Mac takes a few seconds to answer." else "Couldn't send the wake-up." }
            }) { Text("Wake the Mac") }
        }
        if (wake.isEmpty()) Text("To wake the Mac from here, turn on Wake for network access in its Energy settings; Lumiere learns its address the next time it answers.",
            style = MaterialTheme.typography.labelMedium)
        if (saved.isNotEmpty()) {
            Text("Downloaded", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 20.dp))
            LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(saved, key = { it.id }) { d ->
                    LButton(primary = false, modifier = Modifier.width(280.dp), onClick = { state.push(Screen.Player(d.id, null)) }) {
                        Text(d.item.seriesName?.let { "$it · ${d.item.episodeLabel ?: d.item.name}" } ?: d.item.name, maxLines = 1)
                    }
                }
            }
        }
    }
}
