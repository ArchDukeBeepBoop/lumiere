package app.lumiere.android.player

import android.view.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.api.Item
import app.lumiere.android.api.Projection
import app.lumiere.android.api.Server
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.Trickplay
import app.lumiere.android.api.projectionIn
import app.lumiere.android.api.stereoLayoutOf
import app.lumiere.android.api.surroundEyes
import app.lumiere.android.api.trickplaySheet

/**
 * The Theater, on a Quest: a film leaves the window and plays on a screen of
 * its own — a video layer the headset draws directly, sharp at any size,
 * curved or flat, in true 3D for a 3D film, or wrapped round you for 180°
 * and 360°. The player asks with [request]; the headset's module puts up the
 * screen and hands back its [surface]; the player draws there until the
 * film ends, then takes its picture back. [controls] is what the floating
 * transport works, and [cues] are the captions it shows by the screen.
 */
object Theater {
    /** Set by the Quest's spatial app; elsewhere every film plays in its window. */
    var enabled = false

    /** The screen a film wants: flat or round you, how its eyes are laid out, and its picture's size. */
    data class Request(val projection: Projection, val eyes: StereoLayout, val width: Int, val height: Int)

    var request by mutableStateOf<Request?>(null)
    var surface by mutableStateOf<Surface?>(null)

    /** A film is on the Theater's screen now. */
    val active: Boolean get() = request != null

    /** What the transport needs of the film that's playing. */
    class Controls(
        val player: ExoPlayer, val clock: Clock, val title: String, val detail: String?,
        val server: Server, val itemId: String, val trickplay: () -> Trickplay?,
        /** Leave the film, as Back would. */
        val exit: () -> Unit,
    )

    var controls by mutableStateOf<Controls?>(null)
    var cues by mutableStateOf<List<Cue>>(emptyList())
    /**
     * The colour of the scene on screen now, every two seconds from the
     * film's own preview frames (trickplay), for the room and the hall to
     * take its light — a sunset glows orange, night goes blue. Null without
     * preview frames; the poster's colour is used then.
     */
    var screenColour by mutableStateOf<androidx.compose.ui.graphics.Color?>(null)

    /** Which preview sheet, and which tile on it (column, row), shows the film at [seconds]. */
    fun tileAt(t: Trickplay, seconds: Double): Triple<Int, Int, Int> {
        val index = (seconds * 1000 / t.intervalMs).toInt().coerceIn(0, (t.count - 1).coerceAtLeast(0))
        val perSheet = (t.tiles * t.tiles).coerceAtLeast(1)
        val cell = index % perSheet
        return Triple(index / perSheet, cell % t.tiles.coerceAtLeast(1), cell / t.tiles.coerceAtLeast(1))
    }

    /** The average colour of a [w] × [h] tile at ([x0], [y0]), read through [pixel], every [step] pixels. */
    fun averageOf(x0: Int, y0: Int, w: Int, h: Int, step: Int = 6, pixel: (Int, Int) -> Int): androidx.compose.ui.graphics.Color? {
        var r = 0L; var g = 0L; var b = 0L; var n = 0
        var y = y0
        while (y < y0 + h) {
            var x = x0
            while (x < x0 + w) {
                val p = pixel(x, y); r += (p shr 16) and 255; g += (p shr 8) and 255; b += p and 255; n++
                x += step
            }
            y += step
        }
        return if (n == 0) null else androidx.compose.ui.graphics.Color((r / n).toInt(), (g / n).toInt(), (b / n).toInt())
    }
    /** The next episode, when there is one: the transport's Next. */
    var next by mutableStateOf<(() -> Unit)?>(null)

    /** The window's own player screen asked for in front (its tracks, info), over the Theater. */
    var windowAsked by mutableStateOf(false)

    /** When you last did anything — a button, a pinch, the transport — so it shows. */
    var lastActivity by mutableLongStateOf(0L)
        private set

    fun poke(now: Long = clockMs()) { lastActivity = now }

    /** Milliseconds on a clock that only goes forward (the same one the headset's director reads). */
    fun clockMs(): Long = System.nanoTime() / 1_000_000

    /** How long the transport stays after the last touch while a film plays. */
    const val TRANSPORT_LINGER_MS = 4_000L

    /** Whether the transport shows: always when paused or asked for, else for a few seconds after a touch. */
    fun transportShows(playing: Boolean, now: Long, last: Long = lastActivity): Boolean =
        !playing || now - last < TRANSPORT_LINGER_MS
}

/**
 * The film [item] sent to the Theater's screen once its picture's size is
 * known, and taken back when it ends. True while the Theater has it, for the
 * window's own 3D handling to stand aside. [is3D] is what the library says
 * of a flat film's eyes when its name doesn't.
 */
@Composable
fun rememberTheater(
    view: PlayerView, player: ExoPlayer, item: Item?, clock: Clock, server: Server, is3D: Boolean,
    trickplay: () -> Trickplay?, exit: () -> Unit,
): Boolean {
    if (!Theater.enabled || item == null) return false
    var size by remember(player) { mutableStateOf(player.videoSize) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) { size = videoSize }
            override fun onCues(cueGroup: CueGroup) { Theater.cues = cueGroup.cues }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    val names = listOfNotNull(item.name, item.path?.substringAfterLast('/'))
    val projection = remember(item.id, size) { projectionIn(names, size.width, size.height) }
    val eyes = remember(item.id, projection, size) {
        if (projection == Projection.FLAT) stereoLayoutOf(item, is3D) else surroundEyes(names, projection, size.width, size.height)
    }
    // Once the picture's size is known, so the screen is made once, at its shape.
    LaunchedEffect(item.id, projection, eyes, size.width, size.height) {
        Theater.request = if (size.width <= 0 || size.height <= 0) null
            else Theater.Request(projection, eyes, size.width, size.height)
    }
    // The screen's surface, once the headset has made it; the window's own picture again when it goes.
    val surface = Theater.surface
    DisposableEffect(surface) {
        val taken = surface != null
        if (taken) player.setVideoSurface(surface)
        onDispose {
            if (taken) { player.clearVideoSurface(surface); view.player = null; view.player = player }
        }
    }
    // The scene's light, from the film's own preview frames, every two seconds.
    @Suppress("DEPRECATION") val images = coil.compose.LocalImageLoader.current
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(item.id) {
        while (true) {
            kotlinx.coroutines.delay(2_000)
            val t = trickplay() ?: continue
            val (sheet, col, row) = Theater.tileAt(t, clock.now())
            val request = coil.request.ImageRequest.Builder(context).data(server.trickplaySheet(item.id, t.width, sheet))
                .allowHardware(false).build()
            val bitmap = (images.execute(request).drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap ?: continue
            val x0 = col * t.width; val y0 = row * t.height
            if (x0 + t.width > bitmap.width || y0 + t.height > bitmap.height) continue
            Theater.screenColour = Theater.averageOf(x0, y0, t.width, t.height) { x, y -> bitmap.getPixel(x, y) }
        }
    }
    val title = if (item.isEpisode) item.seriesName ?: item.name else item.name
    val detail = item.takeIf { it.isEpisode }?.let { listOfNotNull(it.episodeLabel, it.name).joinToString(" · ") }
    DisposableEffect(player, item.id) {
        Theater.controls = Theater.Controls(player, clock, title, detail, server, item.id, trickplay, exit)
        Theater.poke()
        onDispose {
            Theater.controls = null
            Theater.request = null
            Theater.cues = emptyList()
            Theater.windowAsked = false
            Theater.screenColour = null
            Theater.next = null
        }
    }
    return true
}
