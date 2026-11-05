package app.lumiere.android.player

import android.view.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

/**
 * The Theater, on a Quest: a film leaves the window and plays on a screen of
 * its own in the room — a video layer the headset draws directly, sharp at
 * any size — while the window comes down near your hands with the player's
 * own controls. The player asks with [request] once the picture's size is
 * known; the Quest's room puts up the screen and hands back its [surface];
 * the player draws there until the film ends, then takes its picture back.
 * Off everywhere but the Quest, where every film plays in its window.
 */
object Theater {
    /** Set by the Quest's room (app/src/quest's LumiereSpace). */
    @Volatile var enabled = false

    /**
     * The screen a film wants: its picture's size, for the screen's shape, and
     * which title and file it is, for the Quest to tell 3D, 180° and 360° apart.
     */
    data class Request(val width: Int, val height: Int, val itemId: String = "", val name: String = "")

    var request by mutableStateOf<Request?>(null)
    var surface by mutableStateOf<Surface?>(null)

    /** A film is on the Theater's screen now. */
    val active: Boolean get() = request != null

    /** The film's captions, drawn under its screen rather than in the window. */
    var cues by mutableStateOf<List<Cue>>(emptyList())

    /**
     * A button of the room's own on the player's transport bar while a film is
     * on the Theater (the Quest's wall mount): its label and what it does.
     */
    var barButton by mutableStateOf<Pair<String, () -> Unit>?>(null)

    /** The player's own controls are up (its transport, a menu, its tabs): the window shows near your hands then. */
    var chromeUp by mutableStateOf(false)

    /**
     * The room draws its own transport under the film (the Quest's bar): the
     * window then shows only for a menu or a question, never for the transport.
     */
    @Volatile var ownBar = false

    /** The film's player while it is on the Theater, for the room's own transport. */
    var player by mutableStateOf<Player?>(null)

    /**
     * The film's own time (Clock): the player's position is wrong for audio the
     * server converts, whose stream starts where it was asked to. Set by the player.
     */
    var clock by mutableStateOf<Clock?>(null)

    /** Skip Intro, Skip Credits or the next episode, offered now: its words and what it does. */
    var offer by mutableStateOf<Pair<String, () -> Unit>?>(null)

    /** Opens one of the player's menus in the window: "Audio", "Subtitles", "More" or "Episodes". */
    var open: ((String) -> Unit)? = null

    /** The player's own menus, "Audio", "Subtitles" or "More", for the room to show its own way. */
    internal var entries: ((String) -> List<Entry>)? = null

    /** The room's own rows in the player's More menu (the screen's size, your wall), while a film plays. */
    internal var menu: (() -> List<Entry>)? = null
}

/**
 * The film sent to the Theater's screen once its picture's size is known,
 * and taken back when it ends. True while the Theater has it, so the window
 * stops drawing its own captions.
 */
@Composable
fun rememberTheater(view: PlayerView, player: ExoPlayer, itemId: String?, name: String = ""): Boolean {
    if (!Theater.enabled || itemId == null) return false
    var size by remember(player) { mutableStateOf(player.videoSize) }
    DisposableEffect(player) {
        Theater.player = player
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) { size = videoSize }
            override fun onCues(cueGroup: CueGroup) { Theater.cues = cueGroup.cues }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); if (Theater.player === player) Theater.player = null }
    }
    // Once the picture's size is known, so the screen is made once, at its shape.
    LaunchedEffect(itemId, size.width, size.height) {
        Theater.request = if (size.width <= 0 || size.height <= 0) null else Theater.Request(size.width, size.height, itemId, name)
    }
    // The screen's surface, once the room has made it; the window's own picture again when it goes.
    val surface = Theater.surface
    // Keyed on the player too: one rebuilt mid-film (subtitles refused) takes the screen as well.
    DisposableEffect(surface, player) {
        val taken = surface != null
        if (taken) player.setVideoSurface(surface)
        onDispose {
            if (taken) { player.clearVideoSurface(surface); view.player = null; view.player = player }
        }
    }
    DisposableEffect(player, itemId) {
        onDispose {
            Theater.request = null
            Theater.cues = emptyList()
            Theater.chromeUp = false
            Theater.clock = null
            Theater.offer = null
            Theater.open = null
            Theater.entries = null
        }
    }
    return true
}
