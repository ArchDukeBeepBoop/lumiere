package app.lumiere.android.ui

import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.size
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import java.util.Calendar

/** Last time anyone pressed or touched anything; set by the activity. */
object Idle {
    /** A film left partway; the screensaver offers it back. */
    var leftOff: Item? = null
    /** Whether OK on the screensaver resumes rather than opens. */
    var resumes = false
    /** What the screensaver has up, for OK to open. */
    var showing: Item? = null
    var last by mutableLongStateOf(System.currentTimeMillis())
    fun poke() { last = System.currentTimeMillis() }
}

/**
 * After a few still minutes on a menu, backdrops of the library drift slowly
 * across the screen — a projected menu should not sit burning one picture
 * into the wall. Any button ends it. Never anything private.
 */
@Composable
fun Screensaver(state: AppState, pool: List<Item>) {
    val minutes = state.settings.screensaverMinutes
    if (minutes <= 0) return
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(5_000); now = System.currentTimeMillis() } }
    if (now - Idle.last < minutes * 60_000L) return
    // The screensaver means nobody is watching: the room shuts, back to Home.
    LaunchedEffect(Unit) { if (state.roomOpen) { state.closeRoom(); while (state.top != app.lumiere.android.Screen.Home && state.pop()) Unit } }
    val server = state.server ?: return
    // Music playing: its cover drifts instead of the films, with the song under it.
    app.lumiere.android.music.Music.current?.takeIf { app.lumiere.android.music.Music.isPlaying }?.let { t ->
        Idle.showing = null
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            AsyncImage(server.imageUrl(t.albumId ?: t.id, "Primary", null, 640), null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().graphicsLayer { alpha = 0.3f })
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                AsyncImage(server.imageUrl(t.albumId ?: t.id, "Primary", null, 640), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(320.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp)))
                Text(t.name, style = MaterialTheme.typography.headlineSmall, color = Color.White, modifier = Modifier.padding(top = 18.dp))
                Text(t.artists.joinToString(", ").ifEmpty { t.albumArtist ?: "" }, style = MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.7f))
            }
        }
        return
    }
    // A film left partway comes first, offered back with Resume.
    val left = Idle.leftOff?.takeIf { !state.hides(it.libraryId) }
    val pictures = remember(pool, left) { listOfNotNull(left) + pool.filter { it.backdropTag != null && !state.hides(it.libraryId) && it.id != left?.id }.shuffled() }
    if (pictures.isEmpty()) return
    var index by remember { mutableIntStateOf(0) }
    LaunchedEffect(pictures) { while (true) { delay(12_000); index = (index + 1) % pictures.size } }
    // OK on the screensaver opens what it is showing.
    androidx.compose.runtime.DisposableEffect(pictures, index) {
        Idle.showing = pictures[index]
        Idle.resumes = left != null && pictures[index].id == left.id
        onDispose { Idle.showing = null }
    }
    val drift = rememberInfiniteTransition(label = "drift")
    val scale by drift.animateFloat(1.04f, 1.14f, infiniteRepeatable(tween(12_000, easing = LinearEasing), RepeatMode.Reverse), label = "s")
    // A slow sideways drift too, as Apple's Aerial screensavers move.
    val pan by drift.animateFloat(-0.03f, 0.03f, infiniteRepeatable(tween(24_000, easing = LinearEasing), RepeatMode.Reverse), label = "p")
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Crossfade(pictures[index], animationSpec = tween(1500), label = "saver") { item ->
            Box(Modifier.fillMaxSize()) {
                AsyncImage(imageFor(item, server, CardShape.Wide, 1280), null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().graphicsLayer {
                        if (!app.lumiere.android.Motion.reduced) { scaleX = scale; scaleY = scale; translationX = size.width * pan }
                    })
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.6f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.8f))))
                Column(Modifier.align(Alignment.BottomStart).padding(48.dp)) {
                    Text(item.name, style = MaterialTheme.typography.headlineLarge, color = Color.White.copy(alpha = 0.85f))
                    item.year?.let { Text("$it", style = MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.6f)) }
                    Text(if (left != null && item.id == left.id) "Press OK to resume" else "Press OK to watch", style = MaterialTheme.typography.labelLarge, color = Color.White,
                        modifier = Modifier.padding(top = 14.dp).background(Color.White.copy(alpha = 0.18f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                            .padding(horizontal = 16.dp, vertical = 8.dp))
                }
                TvClock(state, Modifier.align(Alignment.TopEnd).padding(36.dp))
            }
        }
    }
}

/** From 10 pm to 6 am, menus a shade darker. Not over a film. */
@Composable
fun NightDim(state: AppState) {
    if (!state.settings.dimsAtNight) return
    var hour by remember { mutableIntStateOf(Calendar.getInstance().get(Calendar.HOUR_OF_DAY)) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY) } }
    if (hour in 6..21) return
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
}

/**
 * A four-digit PIN before Settings or the private room, on a shared device
 * that has no screen lock of its own — the projector. Digits by the remote's
 * number keys or the on-screen pad.
 */
@Composable
fun PinPad(title: String, onDone: (String) -> Unit, onCancel: () -> Unit) {
    var entered by remember { mutableStateOf("") }
    androidx.activity.compose.BackHandler(onBack = onCancel)
    // The remote starts on 5, the middle of the pad, and stays on the pad.
    val middle = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { delay(80); runCatching { middle.requestFocus() } }
    fun press(key: String) {
        when (key) {
            "⌫" -> entered = entered.dropLast(1)
            "✕" -> onCancel()
            else -> if (entered.length < 4) {
                entered += key
                if (entered.length == 4) { onDone(entered); entered = "" }
            }
        }
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.8f)), contentAlignment = Alignment.Center) {
        Column(Modifier.holdsRemote().ignoreHeldOk().onPreviewKeyEvent { e ->
                // The remote's own number keys type straight in.
                val k = e.nativeKeyEvent
                if (k.action == android.view.KeyEvent.ACTION_DOWN && k.keyCode in android.view.KeyEvent.KEYCODE_0..android.view.KeyEvent.KEYCODE_9) {
                    press((k.keyCode - android.view.KeyEvent.KEYCODE_0).toString()); true
                } else if (k.action == android.view.KeyEvent.ACTION_DOWN && k.keyCode == android.view.KeyEvent.KEYCODE_DEL) { press("⌫"); true } else false
            }.frosted(16).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Text("●".repeat(entered.length) + "○".repeat(4 - entered.length), style = MaterialTheme.typography.headlineLarge)
            listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("⌫", "0", "✕")).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { key ->
                        LButton(primary = false, modifier = Modifier.width(72.dp).then(if (key == "5") Modifier.focusRequester(middle) else Modifier),
                            onClick = { press(key) }) { Text(key) }
                    }
                }
            }
        }
    }
}
