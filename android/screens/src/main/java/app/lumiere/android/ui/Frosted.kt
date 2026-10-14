package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import java.text.DateFormat
import java.util.Date

/**
 * tvOS's frosted panels: the picture behind shows through, dimmed, under a
 * fine light edge. Android 11 cannot blur what lies behind a panel, so the
 * frost is translucency rather than blur — the same calm, without the cost.
 */
fun Modifier.frosted(radius: Int = 18): Modifier = this
    .background(androidx.compose.ui.graphics.lerp(Palette.surface, Ambient.colour ?: Palette.surface, 0.3f).copy(alpha = 0.82f),
        RoundedCornerShape(radius.dp))
    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(radius.dp))

/** The time, top right, as tvOS shows it — on Home and in a paused film. */
@Composable
fun TvClock(state: app.lumiere.android.AppState, modifier: Modifier = Modifier) {
    if (!state.settings.showsClock) return
    var now by remember { mutableStateOf(Date()) }
    LaunchedEffect(Unit) { while (true) { now = Date(); kotlinx.coroutines.delay(15_000) } }
    Text(DateFormat.getTimeInstance(DateFormat.SHORT).format(now), modifier = modifier,
        style = androidx.compose.material3.MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.85f))
}

/** The time on its own, for places without the app's state (the paused player's top bar). */
@Composable
fun ClockText() {
    var now by remember { mutableStateOf(Date()) }
    LaunchedEffect(Unit) { while (true) { now = Date(); kotlinx.coroutines.delay(15_000) } }
    Text(DateFormat.getTimeInstance(DateFormat.SHORT).format(now),
        style = androidx.compose.material3.MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.85f))
}

/**
 * The film's own colour, for the frosted panels over it — tvOS tints its
 * panels with the picture behind. Taken once per title from a 24-pixel copy of
 * its backdrop: an average, not a frame grab, which the projector can afford.
 */
object Ambient {
    var colour by mutableStateOf<Color?>(null)

    suspend fun learn(context: android.content.Context, url: String?) {
        colour = null
        colour = average(context, url)
    }

    /** The average colour of a picture, from a 24-pixel copy of it. */
    suspend fun average(context: android.content.Context, url: String?): Color? {
        if (url == null) return null
        val result = coil.Coil.imageLoader(context).execute(coil.request.ImageRequest.Builder(context).data(url)
            .size(24).allowHardware(false).build())
        val bmp = (result.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap ?: return null
        var r = 0L; var g = 0L; var b = 0L; var n = 0
        for (x in 0 until bmp.width) for (y in 0 until bmp.height) {
            val p = bmp.getPixel(x, y); r += (p shr 16) and 255; g += (p shr 8) and 255; b += p and 255; n++
        }
        return if (n > 0) Color((r / n).toInt(), (g / n).toInt(), (b / n).toInt()) else null
    }
}
