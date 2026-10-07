package app.lumiere.android.tv

import app.lumiere.android.ui.holdsRemote
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Diagnostics
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvPill
import app.lumiere.android.ui.frosted
import app.lumiere.android.ui.ignoreHeldOk
import kotlinx.coroutines.launch

/**
 * tvOS's Control Centre, for Home: Menu held brings a small panel of the
 * switches reached for most — the room, motion, night dimming, diagnostics.
 * Back or Menu puts it away.
 */
@Composable
fun QuickToggles(state: AppState) {
    if (!state.quickToggles) return
    val p = state.settings
    val activity = LocalContext.current as? android.app.Activity
    val scope = rememberCoroutineScope()
    var note by remember { mutableStateOf<String?>(null) }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    androidx.activity.compose.BackHandler { state.quickToggles = false }
    Box(Modifier.fillMaxSize().ignoreHeldOk().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.TopEnd) {
        Column(Modifier.holdsRemote().padding(28.dp).width(340.dp).frosted().padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Quick Settings", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 12.dp, bottom = 6.dp))
            if (state.privateLibraries.isNotEmpty() && activity != null)
                TvPill({ state.quickToggles = false; app.lumiere.android.ui.toggleRoom(state, activity) }, Modifier.focusRequester(first)) {
                    Text(if (state.roomOpen) "Leave Private Room" else "Private Room")
                }
            if (app.lumiere.android.music.Music.current != null) TvPill({ app.lumiere.android.music.Music.stop(); state.quickToggles = false }) {
                Text("Stop Music")
            }
            if (app.lumiere.android.music.Music.current != null) {
                val m = app.lumiere.android.music.Music
                val left = m.sleepAt?.let { ((it - System.currentTimeMillis()) / 60_000).coerceAtLeast(0) }
                Text("Music sleep timer" + (left?.let { " · $it min left" } ?: ""), style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(start = 12.dp, top = 6.dp))
                androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf(15, 30, 60).forEach { n -> TvPill({ m.sleepIn(n) }, selected = false) { Text("$n") } }
                    TvPill({ m.sleepIn(null) }, selected = m.sleepAt == null) { Text("Off") }
                }
            }
            TvPill({ p.reduceMotion = !p.reduceMotion }, if (state.privateLibraries.isEmpty()) Modifier.focusRequester(first) else Modifier,
                selected = p.reduceMotion) { Text("Reduce Motion · ${if (p.reduceMotion) "On" else "Off"}") }
            TvPill({ p.dimsAtNight = !p.dimsAtNight }, selected = p.dimsAtNight) { Text("Dim at Night · ${if (p.dimsAtNight) "On" else "Off"}") }
            if (p.watchlist.isNotEmpty()) TvPill({ p.watchlist = emptyList(); note = "Up Next additions cleared." }) {
                Text("Clear Up Next additions (${p.watchlist.size})")
            }
            TvPill({ state.server?.let { s -> scope.launch { note = if (Diagnostics.send(s)) "Diagnostics sent." else "Couldn't reach the Mac." } } }) {
                Text("Send Diagnostics")
            }
            note?.let { Text(it, color = Palette.accent, modifier = Modifier.padding(start = 12.dp, top = 4.dp)) }
        }
    }
}
