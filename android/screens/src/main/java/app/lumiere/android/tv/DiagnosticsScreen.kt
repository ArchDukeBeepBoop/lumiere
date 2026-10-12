package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppBuild
import app.lumiere.android.AppState
import app.lumiere.android.Diagnostics
import app.lumiere.android.Probe
import app.lumiere.android.SelfTest
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Diagnostics: which build this is, then every part of the app with whether
 * it works — a full check runs on opening, and the parts that report as they
 * run (the places, the walls, captions, sound) add theirs as you use them.
 * Save puts the whole report in Download/Lumiere; Send gives it to the Mac.
 */
@Composable
fun DiagnosticsScreen(state: AppState) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableIntStateOf(0) }
    var raw by remember { mutableStateOf<List<String>>(emptyList()) }
    fun runAll() {
        if (running) return
        running = true
        scope.launch {
            SelfTest.run(context, state)
            raw = withContext(Dispatchers.IO) { Diagnostics.report().lines() }
            running = false; tick++
        }
    }
    LaunchedEffect(Unit) { runAll() }
    // The parts that report as they run: refreshed every couple of seconds while this is open.
    LaunchedEffect(Unit) { while (true) { delay(2000); tick++ } }
    val results = remember(tick) { Probe.all() }
    val order = listOf(Probe.Status.FAIL, Probe.Status.WARN, Probe.Status.OK, Probe.Status.INFO)
    val fails = results.count { it.status == Probe.Status.FAIL }
    val warns = results.count { it.status == Probe.Status.WARN }

    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas).padding(horizontal = 32.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Text("Diagnostics", style = MaterialTheme.typography.headlineLarge, color = Palette.textPrimary)
            Text(AppBuild.stamp, fontFamily = FontFamily.Monospace, fontSize = 14.sp, color = Palette.accent)
            Spacer(Modifier.height(8.dp))
            Text(
                if (running) "Checking everything…"
                else "$fails failing · $warns warnings · ${results.count { it.status == Probe.Status.OK }} working",
                color = if (fails > 0) StatusColor.fail else Palette.textSecondary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LButton(onClick = { runAll() }, enabled = !running) { Text(if (running) "Checking…" else "Check again") }
                LButton(primary = false, onClick = {
                    scope.launch { note = withContext(Dispatchers.IO) { SelfTest.save(context) } }
                }) { Text("Save report") }
                LButton(primary = false, onClick = {
                    val s = state.server ?: run { note = "Not signed in to a server."; return@LButton }
                    scope.launch { note = if (Diagnostics.sendFull(s)) "Sent to the Mac's server log." else "Couldn't reach the server." }
                }) { Text("Send to the Mac") }
                if (results.any { it.area == "start" && it.name == "mode" && it.status == Probe.Status.FAIL } ||
                    context.getSharedPreferences("start", android.content.Context.MODE_PRIVATE).getInt("unsettled", 0) > 0)
                    LButton(primary = false, onClick = {
                        app.lumiere.android.StartGuard.settled(context)
                        note = "Next start will be a full one: close Lumiere and open it again."
                    }) { Text("Start fully next time") }
            }
            note?.let { Text(it, color = Palette.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp)) }
            Text("Use the app (play a film with subtitles, go to the cinema, press Wall) and come back: those parts report here as they run.",
                color = Palette.textMuted, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
        }
        results.groupBy { it.area }.toList()
            .sortedBy { (_, rs) -> rs.minOf { order.indexOf(it.status) } }
            .forEach { (area, rs) ->
                item(key = "h:$area") {
                    Text(area.replaceFirstChar { it.uppercase() }, color = Palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 14.dp, bottom = 2.dp))
                }
                items(rs.sortedBy { order.indexOf(it.status) }, key = { "r:${it.area}/${it.name}" }) { r -> ResultRow(r) }
            }
        item {
            Text("Notes and system log", color = Palette.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 18.dp))
        }
        items(raw) { l ->
            Text(l, fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = Palette.textSecondary,
                modifier = Modifier.focusCard {}.padding(vertical = 1.dp))
        }
    }
}

private object StatusColor {
    val fail = Color(0xFFE5484D)
    val warn = Color(0xFFF5A524)
    val ok = Color(0xFF46A758)
    val info = Color(0xFF6B7381)
    fun of(s: Probe.Status) = when (s) { Probe.Status.FAIL -> fail; Probe.Status.WARN -> warn; Probe.Status.OK -> ok; Probe.Status.INFO -> info }
}

@Composable
private fun ResultRow(r: Probe.Result) {
    val ago = ((System.currentTimeMillis() - r.at) / 1000).let { if (it < 60) "${it}s ago" else "${it / 60} min ago" }
    Row(Modifier.fillMaxWidth().focusCard {}.background(Palette.surface, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top) {
        Box(Modifier.padding(top = 5.dp).size(10.dp).background(StatusColor.of(r.status), CircleShape))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(r.name, color = Palette.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                Text("${r.status} · $ago", color = StatusColor.of(r.status), fontSize = 11.sp)
            }
            Text(r.detail, color = Palette.textSecondary, fontSize = 13.sp)
        }
    }
}
