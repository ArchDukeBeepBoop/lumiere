package app.lumiere.android.music

import android.content.Context
import android.content.Intent
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.audioUrl
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * The music queue and its one player, shared by every screen and kept alive
 * by [PlaybackService] while the app is in the background — the notification
 * and lock-screen controls come from the session that service holds.
 */
@OptIn(UnstableApi::class)
object Music {
    var player: ExoPlayer? = null
        private set
    var server: Server? = null
        private set
    var shuffle by mutableStateOf(false)
        private set
    /** Player.REPEAT_MODE_OFF, _ALL or _ONE. */
    var repeat by mutableIntStateOf(Player.REPEAT_MODE_OFF)
        private set

    var queue by mutableStateOf<List<Item>>(emptyList())
        private set
    var index by mutableIntStateOf(0)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var position by mutableDoubleStateOf(0.0)
        private set
    var duration by mutableDoubleStateOf(0.0)
        private set
    /** Set while the queue came from a private library, so leaving the app does not cut it off. */
    var isPlayingFromRoom = false

    val current: Item? get() = queue.getOrNull(index)

    private var ticker: Job? = null
    private var session = ""

    fun play(context: Context, server: Server, tracks: List<Item>, start: Int = 0, fromRoom: Boolean = false) {
        if (tracks.isEmpty()) return
        val player = ensure(context, server)
        queue = tracks
        isPlayingFromRoom = fromRoom
        player.setMediaItems(tracks.map { mediaItem(server, it) }, start.coerceIn(0, tracks.lastIndex), 0)
        player.prepare()
        player.play()
        context.startService(Intent(context, PlaybackService::class.java))
    }

    fun toggle() = player?.let { if (it.isPlaying) it.pause() else it.play() }
    fun next() = player?.seekToNextMediaItem()
    fun previous() = player?.let { if (it.currentPosition > 3000) it.seekTo(0) else it.seekToPreviousMediaItem() }
    fun seek(seconds: Double) = player?.seekTo((seconds * 1000).toLong())
    fun jump(to: Int) = player?.let { it.seekTo(to, 0); it.play() }

    fun toggleShuffle() = player?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled; shuffle = it.shuffleModeEnabled }

    fun cycleRepeat() = player?.let {
        it.repeatMode = when (it.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
        repeat = it.repeatMode
    }

    /** Up Next reordered: a track moved one place, or taken out. */
    fun move(from: Int, to: Int) {
        val p = player ?: return
        if (from !in queue.indices || to !in queue.indices) return
        p.moveMediaItem(from, to)
        queue = queue.toMutableList().apply { add(to, removeAt(from)) }
        index = p.currentMediaItemIndex
    }

    fun remove(at: Int) {
        val p = player ?: return
        if (at !in queue.indices || at == index) return
        p.removeMediaItem(at)
        queue = queue.toMutableList().apply { removeAt(at) }
        index = p.currentMediaItemIndex
    }

    /** Play this one next, after what is playing. */
    fun playNext(context: Context, server: Server, track: Item) {
        val p = player
        if (p == null || queue.isEmpty()) return play(context, server, listOf(track))
        val at = index + 1
        p.addMediaItem(at, mediaItem(server, track))
        queue = queue.toMutableList().apply { add(at, track) }
    }

    /** When music stops by itself, in millis; null for never. */
    var sleepAt by mutableStateOf<Long?>(null)
    private var sleeper: Job? = null
    fun sleepIn(minutes: Int?) {
        sleeper?.cancel()
        sleepAt = minutes?.let { System.currentTimeMillis() + it * 60_000L }
        if (minutes != null) sleeper = CoroutineScope(Dispatchers.Main).launch { delay(minutes * 60_000L); stop(); sleepAt = null }
    }

    /** Music off: the sound stops, the queue empties, and nothing of it is left on screen. */
    fun stop() {
        player?.stop()
        player?.clearMediaItems()
        isPlaying = false
        position = 0.0
        duration = 0.0
        queue = emptyList()
        isPlayingFromRoom = false
        appContext?.let { app.lumiere.android.widget.NowPlayingWidget.update(it) }
    }

    private fun mediaItem(server: Server, track: Item) = MediaItem.Builder()
        .setUri(server.audioUrl(track.id))
        .setMediaId(track.id)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(track.name)
                .setArtist(track.artists.joinToString(", ").ifEmpty { track.albumArtist })
                .setAlbumTitle(track.album)
                .setArtworkUri(android.net.Uri.parse(
                    server.imageUrl(track.albumId ?: track.id, "Primary", null, 512)))
                .build()
        )
        .build()

    private var appContext: Context? = null

    private fun ensure(context: Context, server: Server): ExoPlayer {
        appContext = context.applicationContext
        if (player != null && this.server === server) return player!!
        player?.release()
        this.server = server
        val built = ExoPlayer.Builder(context.applicationContext)
            .setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(server.http)))
            // Ducks for a notification, pauses for a call or another app.
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
        built.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                app.lumiere.android.widget.NowPlayingWidget.update(context.applicationContext)
                report(if (playing) "Sessions/Playing" else "Sessions/Playing/Progress")
            }
            override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                report("Sessions/Playing/Stopped")
                index = built.currentMediaItemIndex
                app.lumiere.android.widget.NowPlayingWidget.update(context.applicationContext)
                session = UUID.randomUUID().toString().replace("-", "")
            }
        })
        player = built
        ticker?.cancel()
        ticker = CoroutineScope(Dispatchers.Main).launch {
            while (true) {
                position = built.currentPosition / 1000.0
                duration = built.duration.takeIf { it > 0 }?.div(1000.0) ?: 0.0
                delay(if (app.lumiere.android.Device.lowMemory) 500 else 250)
            }
        }
        return built
    }

    /** Play counts and last-played, as the Mac reports them. */
    private fun report(path: String) {
        val p = player ?: return
        val track = current ?: return
        val s = server ?: return
        val ticks = p.currentPosition.coerceAtLeast(0) * 10_000
        val id = session.ifEmpty { UUID.randomUUID().toString().replace("-", "").also { session = it } }
        // Read here, on the main thread: ExoPlayer refuses to be asked from any other.
        val paused = !p.isPlaying
        CoroutineScope(Dispatchers.IO).launch { s.report(path, track.id, ticks, id, paused) }
    }
}
