package app.lumiere.android.tv

import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Animation
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
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
    // Control Center: a frosted column sliding in from the right — the time, what
    // is playing, then square switches that light in their own colour when on.
    val shown = remember { androidx.compose.animation.core.Animatable(1f) }
    LaunchedEffect(Unit) { shown.animateTo(0f, androidx.compose.animation.core.tween(app.lumiere.android.Motion.ms(220))) }
    val music = app.lumiere.android.music.Music
    Box(Modifier.fillMaxSize().ignoreHeldOk().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.CenterEnd) {
        Column(Modifier.holdsRemote().fillMaxHeight().width(380.dp).padding(20.dp)
            .graphicsLayer { translationX = shown.value * size.width }
            .frosted(26).padding(18.dp).verticalScroll(androidx.compose.foundation.rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            app.lumiere.android.ui.ClockText()
            music.current?.let { t ->
                // The music module: cover, song, and its two buttons.
                Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(18.dp)).padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    state.server?.let { srv -> coil.compose.AsyncImage(srv.imageUrl(t.albumId ?: t.id, "Primary", null, 120), null,
                        modifier = Modifier.size(52.dp).background(Palette.surface, RoundedCornerShape(10.dp))) }
                    Column(Modifier.weight(1f)) {
                        Text(t.name, maxLines = 1, style = MaterialTheme.typography.titleSmall)
                        Text(t.artists.joinToString(", ").ifEmpty { t.albumArtist ?: "" }, maxLines = 1, style = MaterialTheme.typography.labelMedium)
                    }
                    app.lumiere.android.ui.LIconButton(onClick = { music.toggle() }) {
                        androidx.compose.material3.Icon(if (music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Play or pause",
                            tint = app.lumiere.android.ui.pillTint(Color.White))
                    }
                    app.lumiere.android.ui.LIconButton(onClick = { music.stop(); state.quickToggles = false }) {
                        androidx.compose.material3.Icon(Icons.Default.Stop, "Stop", tint = app.lumiere.android.ui.pillTint(Color.White))
                    }
                }
            }
            val tiles = buildList<Tile> {
                if (state.privateLibraries.isNotEmpty() && activity != null)
                    add(Tile("Private Room", Icons.Default.Lock, state.roomOpen, Color(0xFFAF52DE)) {
                        state.quickToggles = false; app.lumiere.android.ui.toggleRoom(state, activity) })
                add(Tile("Reduce Motion", Icons.Default.Animation, p.reduceMotion, Color(0xFF007AFF)) { p.reduceMotion = !p.reduceMotion })
                add(Tile("Dim at Night", Icons.Default.DarkMode, p.dimsAtNight, Color(0xFF5856D6)) { p.dimsAtNight = !p.dimsAtNight })
                add(Tile("Night Sound", Icons.Default.NightsStay, p.nightAuto, Color(0xFFFF9500)) { p.nightAuto = !p.nightAuto })
                add(Tile("Phone Remote", Icons.Default.PhoneIphone, p.phoneRemote, Color(0xFF34C759)) { p.phoneRemote = !p.phoneRemote })
                add(Tile("Diagnostics", Icons.Default.BugReport, false, Color(0xFF8E8E93)) {
                    state.server?.let { srv -> scope.launch { note = if (Diagnostics.send(srv)) "Diagnostics sent." else "Couldn't reach the Mac." } } })
            }
            tiles.chunked(3).forEachIndexed { r, row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEachIndexed { c, t -> TileButton(t, if (r == 0 && c == 0) Modifier.focusRequester(first) else Modifier) }
                }
            }
            if (music.current != null) {
                val left = music.sleepAt?.let { ((it - System.currentTimeMillis()) / 60_000).coerceAtLeast(0) }
                Text("Music sleep timer" + (left?.let { " · $it min left" } ?: ""), style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf(15, 30, 60).forEach { n -> TvPill({ music.sleepIn(n) }) { Text("$n") } }
                    TvPill({ music.sleepIn(null) }, selected = music.sleepAt == null) { Text("Off") }
                }
            }
            if (p.watchlist.isNotEmpty()) TvPill({ p.watchlist = emptyList(); note = "Up Next additions cleared." }) {
                Text("Clear Up Next additions (${p.watchlist.size})")
            }
            note?.let { Text(it, color = Palette.accent) }
        }
    }
}

private class Tile(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val on: Boolean,
                   val colour: Color, val onClick: () -> Unit)

/** A Control Center switch: a rounded square, its own colour when on, white when the remote is on it. */
@Composable
private fun TileButton(t: Tile, modifier: Modifier) {
    Column(Modifier.width(92.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        androidx.tv.material3.Surface(onClick = t.onClick, modifier = modifier.size(74.dp),
            shape = androidx.tv.material3.ClickableSurfaceDefaults.shape(RoundedCornerShape(22.dp)),
            scale = androidx.tv.material3.ClickableSurfaceDefaults.scale(focusedScale = 1.08f),
            colors = androidx.tv.material3.ClickableSurfaceDefaults.colors(
                containerColor = if (t.on) t.colour else Color.White.copy(alpha = 0.12f), contentColor = Color.White,
                focusedContainerColor = Color.White, focusedContentColor = if (t.on) t.colour else Color.Black)) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                androidx.tv.material3.Icon(t.icon, null, Modifier.size(30.dp))
            }
        }
        Text(t.label, style = MaterialTheme.typography.labelMedium, maxLines = 1)
    }
}
