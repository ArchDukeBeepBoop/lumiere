package app.lumiere.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.LyricLine
import app.lumiere.android.api.Server
import app.lumiere.android.api.Trickplay
import app.lumiere.android.api.currentLyric
import app.lumiere.android.api.lyrics
import app.lumiere.android.music.Music
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * What floats in front of you on a Quest, below the screen, as Vision Pro's
 * ornaments do: Up Next in the credits, a strip of the film's frames while
 * you scrub, or the song playing with its sung line. The player publishes
 * here; the headset's module shows the panel only while there is something.
 */
object Floating {
    /** Set by the Quest's spatial app; the phone, TV and 2D window keep things in the picture. */
    var enabled = false

    class UpNextOffer(val next: Item, val server: Server, val counting: Boolean, val onPlay: () -> Unit, val onDismiss: () -> Unit)
    class Scrub(val server: Server, val id: String, val t: Trickplay, val seconds: Float)

    var upNext by mutableStateOf<UpNextOffer?>(null)
    var scrub by mutableStateOf<Scrub?>(null)

    /** A song playing while you do something else: not over a film, nor beside Now Playing itself. */
    private val listening: Boolean get() = Music.current != null && Music.isPlaying &&
        OpenApp.state?.top.let { it !is Screen.Player && it != Screen.NowPlaying }
    val showing: Boolean get() = enabled && (upNext != null || scrub != null || listening)

    @Composable
    fun Ornament() {
        LumiereTheme {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                val offer = upNext
                val s = scrub
                when {
                    s != null -> FilmStrip(s)
                    offer != null -> UpNextOrb(offer)
                    listening -> NowSinging()
                }
            }
        }
    }
}

@Composable
private fun FilmStrip(s: Floating.Scrub) {
    val index = ((s.seconds * 1000) / s.t.intervalMs).toInt().coerceIn(0, (s.t.count - 1).coerceAtLeast(0))
    val w = 150.dp
    val h = w * (s.t.height.toFloat() / s.t.width)
    Column(Modifier.frosted(24).padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (offset in -2..2) {
                val i = index + offset
                val big = offset == 0
                val scale = if (big) 1f else if (kotlin.math.abs(offset) == 1) 0.72f else 0.5f
                if (i in 0 until s.t.count) app.lumiere.android.player.Tile(s.server, s.id, s.t, i, w * scale, h * scale, if (big) 1f else 0.6f)
                else Spacer(Modifier.width(w * scale))
            }
        }
        Text(app.lumiere.android.music.clock(s.seconds.toDouble()), color = Color.White, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun UpNextOrb(o: Floating.UpNextOffer) {
    var left by remember(o.next.id) { mutableIntStateOf(10) }
    LaunchedEffect(o.next.id, o.counting) {
        if (!o.counting) return@LaunchedEffect
        while (left > 0) { delay(1000); left-- }
        o.onPlay()
    }
    Row(Modifier.frosted(28).padding(14.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        AsyncImage(imageFor(o.next, o.server, CardShape.Wide, 480), null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(240.dp, 135.dp).clip(RoundedCornerShape(12.dp)))
        Column(Modifier.width(300.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (o.counting) "Up Next in $left" else "Up Next", style = MaterialTheme.typography.labelMedium, color = Palette.accent)
            Text(o.next.name, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LButton(onClick = o.onPlay) { Text("Play Now") }
                LButton(primary = false, onClick = o.onDismiss) { Text("Not Now") }
            }
        }
    }
}

@Composable
private fun NowSinging() {
    val track = Music.current ?: return
    val server = OpenApp.state?.server ?: return
    var lines by remember(track.id) { mutableStateOf<List<LyricLine>?>(null) }
    var at by remember { mutableStateOf(0.0) }
    LaunchedEffect(track.id) { lines = runCatching { server.lyrics(track.id) }.getOrNull() }
    LaunchedEffect(track.id) { while (true) { at = (Music.player?.currentPosition ?: 0L) / 1000.0; delay(250) } }
    val sung = lines?.let { l -> currentLyric(l, at)?.let { l.getOrNull(it)?.text } }
    Row(Modifier.frosted(28).padding(16.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        AsyncImage(imageFor(track, server, CardShape.Poster, 300), null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(150.dp).clip(RoundedCornerShape(10.dp)))
        Column(Modifier.width(420.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(track.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(track.artists.joinToString(", ").ifEmpty { track.albumArtist ?: "" }, color = Palette.textSecondary, maxLines = 1)
            if (sung != null) Text(sung, style = MaterialTheme.typography.headlineSmall, color = Palette.accent, maxLines = 2)
        }
    }
}
