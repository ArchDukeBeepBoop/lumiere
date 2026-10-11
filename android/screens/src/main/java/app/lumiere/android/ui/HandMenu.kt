package app.lumiere.android.ui

import android.media.AudioManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.VolumeDown
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.lumiere.android.Stage
import app.lumiere.android.player.Theater
import kotlinx.coroutines.delay

/**
 * The hand menu: raise a hand and look at it, and a little row of glass
 * comes by it — in a film, back ten seconds, play or pause, forward ten;
 * and always the volume, the place, and everything brought back before you
 * — for the other hand to press, without reaching for a panel. It goes a
 * moment after you lower your hand (HandRaise).
 */
object HandMenu {
    /** When it was last pressed: it stays a while after, even with the hand lowered. */
    var touchedAt by mutableLongStateOf(Long.MIN_VALUE / 2)
        private set

    fun touched() { touchedAt = Theater.clockMs(); Theater.poke() }

    @Composable
    fun Panel() = LumiereTheme {
        val context = LocalContext.current
        val audio = remember { context.getSystemService(AudioManager::class.java) }
        val c = Theater.controls
        var playing by remember(c) { mutableStateOf(c?.player?.isPlaying == true) }
        LaunchedEffect(c) { while (c != null) { playing = c.player.isPlaying; delay(300) } }
        fun press(action: () -> Unit) { touched(); action() }
        fun volume(dir: Int) = runCatching { audio?.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI) }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Row(Modifier.spatialGlass(40).padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                if (c != null) {
                    GlassButton(Icons.Default.Replay10, "Back 10 seconds", size = 60.dp) { press { c.clock.seek((c.clock.now() - 10).coerceAtLeast(0.0)) } }
                    GlassButton(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play",
                        chosen = true, size = 64.dp) { press { if (c.player.isPlaying) c.player.pause() else c.player.play() } }
                    GlassButton(Icons.Default.Forward10, "Forward 10 seconds", size = 60.dp) { press { c.clock.seek(c.clock.now() + 10) } }
                } else GlassButton(Icons.Default.GraphicEq, if (Stage.ambience) "Sounds of the place: on" else "Sounds of the place: off",
                    chosen = Stage.ambience, size = 60.dp) { press { Stage.toggleAmbience() } }
                GlassButton(Icons.Default.VolumeDown, "Quieter", size = 60.dp) { press { volume(AudioManager.ADJUST_LOWER) } }
                GlassButton(Icons.Default.VolumeUp, "Louder", size = 60.dp) { press { volume(AudioManager.ADJUST_RAISE) } }
                GlassButton(placeIcon(Stage.place), "Next place: you're in ${Stage.place.label}", caption = placeCaption(Stage.place), size = 60.dp) {
                    press { Stage.nextPlace() }
                }
                GlassButton(Icons.Default.CenterFocusStrong, "Bring everything here", size = 60.dp) { press { Stage.bringHere() } }
            }
        }
    }
}
