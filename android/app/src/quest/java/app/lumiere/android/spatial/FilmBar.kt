package app.lumiere.android.spatial

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.player.Theater
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.Symbols

/**
 * The film's controls in the room, as Apple TV and NEX keep theirs: one slim
 * glass bar floating low before you, never the window. Play, ten seconds
 * either way, where you are in the film, Audio and Subtitles, Places, and
 * More (3D, Screen Size). It comes up with any button or pinch, stays while
 * you point at it or the film is paused, and fades after a few seconds.
 * Faded it is still there to point at, as NEX's controls come back with a
 * click anywhere: the first pinch only brings it up, so a stray one never
 * pauses the film. Menus open just above it (BarMenu), never the window,
 * and the bar steps aside for Where to Watch and for the player's questions.
 */
object FilmBar {
    /** Panel width in the room; the panel is [ASPECT] times wider than tall. */
    const val WIDTH_M = 0.62f
    const val ASPECT = 5.2f
    const val WIDTH_DP = 960f
    private const val SHOWS_MS = 4000L

    private var until by mutableLongStateOf(0L)
    /** The bar's title line: the film or episode, set by the stage. */
    var title by mutableStateOf("")

    /** Up for a few seconds more: a button, a pinch, the pointer over it. */
    fun wake() { until = System.currentTimeMillis() + SHOWS_MS }

    /** Whether it shows now: paused, or woken lately, with nothing else open over the film. */
    fun shown(playing: Boolean, now: Long, until: Long, covered: Boolean): Boolean = !covered && (!playing || now < until)

    private var up by mutableStateOf(true)
    /** The bar is showing now (not faded). */
    val isUp: Boolean get() = up

    /**
     * Seat and Screen Size, as Apple's player keeps its seat picker beside
     * the film: [seats] null where the place fixes your seat (its own drawn
     * screen), [sizes] null where it fixes the screen. Set by the stage.
     */
    class Screen(val seats: List<String>?, val seat: Int, val sizes: List<String>?, val size: Int,
                 val setSeat: (Int) -> Unit, val setSize: (Int) -> Unit)
    var screen by mutableStateOf<Screen?>(null)
    /** Brings the screen and bar back before you; set by the stage. */
    var resetView: () -> Unit = {}

    /** The bar shows Seat and Size instead of the transport, until Done. */
    private var choosing by mutableStateOf(false)

    @Composable
    fun Panel() {
        val player = Theater.player
        var pos by remember { mutableLongStateOf(0L) }
        var dur by remember { mutableLongStateOf(0L) }
        var playing by remember { mutableStateOf(true) }
        var vol by remember { mutableFloatStateOf(1f) }
        LaunchedEffect(player) {
            while (true) {
                // The film's own time (Clock), right for audio the server converts as well.
                val c = Theater.clock
                player?.let { pos = c?.let { k -> (k.now() * 1000).toLong() } ?: it.currentPosition
                    dur = c?.let { k -> (k.duration() * 1000).toLong() } ?: it.duration.coerceAtLeast(0L); playing = it.isPlaying; vol = it.volume }
                // An offer (Skip Intro, Next Episode) keeps the bar up while it stands.
                if (BarMenu.kind != null || Theater.offer != null) wake()
                up = shown(playing, System.currentTimeMillis(), until, Theater.chromeUp || PlacePicker.open)
                kotlinx.coroutines.delay(250)
            }
        }
        val alpha by androidx.compose.animation.core.animateFloatAsState(if (up) 1f else 0f, label = "bar")
        Column(
            Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha }.clip(RoundedCornerShape(36.dp)).background(Palette.canvas.copy(alpha = 0.86f))
                .pointerInput(Unit) { awaitPointerEventScope { while (true) { awaitPointerEvent(); wake() } } }
                .padding(horizontal = 28.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val s = screen
            if (choosing && s != null) { Choosing(s); return@Column }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
                Text("${clock(pos)} / ${clock(dur)}", style = TextStyle(fontSize = 15.sp, color = Palette.textSecondary))
                // Volume at the top right, as Apple's player keeps it: the film's own, under the headset's.
                Pill("−") { player?.let { it.volume = (it.volume - 0.1f).coerceAtLeast(0f) } }
                Box(Modifier.width(56.dp).height(5.dp).clip(CircleShape).background(Palette.textMuted.copy(alpha = 0.5f))) {
                    Box(Modifier.fillMaxWidth(vol).height(5.dp).clip(CircleShape).background(Palette.textPrimary))
                }
                Pill("+") { player?.let { it.volume = (it.volume + 0.1f).coerceAtMost(1f) } }
            }
            Track(if (dur > 0) pos.toFloat() / dur else 0f) { f -> seek(player, f * dur / 1000.0); wake() }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Key(Symbols.audio, "Audio") { BarMenu.open("Audio") }
                Key(Symbols.subtitles, "Subtitles") { BarMenu.open("Subtitles") }
                Spacer(Modifier.weight(1f))
                Key(Symbols.skipBack, "Back 10 Seconds") { seek(player, (pos - 10_000).coerceAtLeast(0) / 1000.0) }
                Key(if (playing) Symbols.pause else Symbols.play, if (playing) "Pause" else "Play", big = true) {
                    player?.let { if (it.isPlaying) it.pause() else it.play() }
                }
                Key(Symbols.skipForward, "Forward 10 Seconds") { seek(player, (pos + 10_000) / 1000.0) }
                Spacer(Modifier.weight(1f))
                // Skip Intro or Next Episode, lit, where the eye already is.
                Theater.offer?.let { (label, act) -> Pill(label, on = true, onClick = act) }
                // The place, by name, one pinch from changing (Where to Watch).
                Pill("${PlacePicker.current().label}  ▾") { PlacePicker.open = true }
                if (screen != null) Pill("Screen") { choosing = true }
                Pill("Reset View") { resetView() }
                Theater.barButton?.let { (label, act) -> Pill(label, onClick = act) }
                Key(Symbols.more, "More") { BarMenu.open("More") }
            }
        }
    }

    /** Seat and Size in place of the transport: the chosen one lit; Done brings the transport back. */
    @Composable
    private fun Choosing(s: Screen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Seat", Modifier.width(64.dp), style = TextStyle(fontSize = 15.sp, color = Palette.textSecondary))
            s.seats?.forEachIndexed { i, n -> Pill(n, on = i == s.seat) { s.setSeat(i) } }
                ?: Text("This place's own", style = TextStyle(fontSize = 15.sp, color = Palette.textMuted))
            Spacer(Modifier.weight(1f))
            Pill("Done", on = true) { choosing = false }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Size", Modifier.width(64.dp), style = TextStyle(fontSize = 15.sp, color = Palette.textSecondary))
            s.sizes?.forEachIndexed { i, n -> Pill(n, on = i == s.size) { s.setSize(i) } }
                ?: Text("This place's own screen", style = TextStyle(fontSize = 15.sp, color = Palette.textMuted))
        }
    }

    /** A word to press: lit when [on]; a first pinch on the faded bar only wakes it. */
    @Composable
    private fun Pill(label: String, on: Boolean = false, onClick: () -> Unit) {
        Text(label, Modifier.padding(horizontal = 4.dp).clip(CircleShape)
            .background(Palette.textPrimary.copy(alpha = if (on) 0.24f else 0.10f))
            .clickable { if (up) onClick(); wake() }.padding(horizontal = 14.dp, vertical = 10.dp),
            style = TextStyle(fontSize = 15.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, color = Palette.textPrimary))
    }

    /** Where you are: a thin line, filled to here; a pinch along it goes there. */
    @Composable
    private fun Track(fraction: Float, onSeek: (Float) -> Unit) {
        Box(Modifier.fillMaxWidth().height(18.dp).pointerInput(Unit) {
            detectTapGestures { o -> if (up) onSeek((o.x / size.width).coerceIn(0f, 1f)) else wake() }
        }, contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth().height(5.dp).clip(CircleShape).background(Palette.textMuted.copy(alpha = 0.5f)))
            Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(5.dp).clip(CircleShape).background(Palette.textPrimary))
        }
    }

    @Composable
    private fun Key(icon: ImageVector, label: String, big: Boolean = false, onClick: () -> Unit) {
        val d = if (big) 64.dp else 52.dp
        Box(Modifier.padding(horizontal = 6.dp).size(d).clip(CircleShape)
            .background(if (big) Palette.textPrimary.copy(alpha = 0.16f) else Color.Transparent)
            .clickable(onClickLabel = label) { if (up) onClick(); wake() }, contentAlignment = Alignment.Center) {
            Icon(icon, label, Modifier.size(if (big) 34.dp else 28.dp), tint = Palette.textPrimary)
        }
    }

    /** To [seconds] in the film's own time, through its Clock where there is one. */
    private fun seek(player: androidx.media3.common.Player?, seconds: Double) {
        Theater.clock?.seek(seconds) ?: player?.seekTo((seconds * 1000).toLong())
    }

    private fun clock(ms: Long): String {
        val s = ms / 1000
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
    }
}
