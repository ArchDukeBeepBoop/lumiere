package app.lumiere.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import app.lumiere.android.api.Segment
import app.lumiere.android.api.Server
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.api.localTrailers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

/**
 * Top Shelf's moving picture, without spoilers: after four seconds on the
 * spotlight the title's own trailer fades over the still (a show's for its
 * episodes), or, with none, a silent stretch of its opening that never runs
 * past a tenth of the way in ([PreviewChoice]). Only while the spotlight has
 * the remote, or on a Quest while it's pointed at; muted; and released the
 * moment it leaves — one decoder, never kept. [onPlaying] hears while the
 * picture is up, so the banner can hold its page until it ends.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun BannerPreview(state: AppState, item: Item?, active: Boolean, onPlaying: (Boolean) -> Unit = {}) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    if (!state.settings.bannerPreviews || item == null || !active || PreviewChoice.trailerOwner(item) == null) return
    var clip by remember(item.id) { mutableStateOf<PreviewClip?>(null) }
    var ready by remember(item.id) { mutableStateOf(false) }
    // The trailer is looked for during the wait, so the picture can start on time.
    LaunchedEffect(item.id) {
        clip = coroutineScope { val found = async { previewFor(server, userId, item) }; delay(4_000); found.await() }
    }
    val chosen = clip ?: return
    val context = LocalContext.current
    val player = remember(chosen) {
        // Through the signed-in client, as the player's own requests go: the Mac
        // refuses a stream without the token. A small read-ahead: it's a glimpse.
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(androidx.media3.exoplayer.source.DefaultMediaSourceFactory(
                androidx.media3.datasource.okhttp.OkHttpDataSource.Factory(server.http)))
            .setLoadControl(androidx.media3.exoplayer.DefaultLoadControl.Builder().setBufferDurationsMs(4_000, 12_000, 1_000, 1_000).build())
            .build().apply {
                volume = 0f
                repeatMode = Player.REPEAT_MODE_OFF
                // Silent, so no sound is decoded at all, nor any subtitle drawn.
                trackSelectionParameters = trackSelectionParameters.buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
                // The clip's end is the file's end as far as the player knows: it can't run past it.
                val clipping = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(chosen.startMs)
                    .apply { chosen.endMs?.let { setEndPositionMs(it) } }.build()
                setMediaItem(MediaItem.Builder().setUri(server.streamUrl(chosen.itemId, chosen.mediaSourceId))
                    .setClippingConfiguration(clipping).build())
                addListener(object : Player.Listener {
                    override fun onRenderedFirstFrame() { ready = true }
                    // The trailer or stretch over: the still again, and the decoder let go.
                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_ENDED) { ready = false; stop() }
                    }
                    override fun onPlayerError(error: PlaybackException) { ready = false }
                })
                prepare(); play()
            }
    }
    DisposableEffect(player) { onDispose { player.release(); onPlaying(false) } }
    LaunchedEffect(ready) { onPlaying(ready) }
    AnimatedVisibility(ready, enter = fadeIn(tween(800)), exit = fadeOut(tween(500))) {
        AndroidView({ PlayerView(it).apply { useController = false; this.player = player
            // The last frame stays while the still fades back, rather than a black flash.
            setKeepContentOnPlayerReset(true)
            resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM } }, Modifier.fillMaxSize())
    }
}

/** The title's trailer, else its opening; null when neither is safe to show. */
private suspend fun previewFor(server: Server, userId: String, item: Item): PreviewClip? {
    val trailers = PreviewChoice.trailerOwner(item)?.let { server.localTrailers(userId, it) }.orEmpty()
    return PreviewChoice.trailer(trailers)
        ?: if (item.isPlayable) PreviewChoice.opening(item, server.segments(item.id)) else null
}

/** What the banner plays: [itemId]'s file from [startMs] to [endMs], or to its end when that is null. */
internal data class PreviewClip(val itemId: String, val mediaSourceId: String?, val startMs: Long, val endMs: Long?)

/**
 * Which moving picture the banner shows, with nothing given away: the
 * title's own trailer, played whole; else its opening, from the end of the
 * intro (or 90 seconds in, past the logos) and never past a tenth of the way
 * through. A film's middle, which the banner used to play, can spoil it.
 */
internal object PreviewChoice {
    /** Where an opening starts when the Mac hasn't marked the intro. */
    const val OPENING_MS = 90_000L
    /** The longest an opening plays before the still returns. */
    const val LONGEST_MS = 90_000L
    /** Shorter than this isn't worth waking a decoder for. */
    const val SHORTEST_MS = 15_000L

    /**
     * Whose trailers to ask for: an episode's are its show's, and a show's or
     * film's its own; a collection or a folder has none to play.
     */
    fun trailerOwner(item: Item): String? = when {
        item.isEpisode -> item.seriesId ?: item.id
        item.isSeries || item.isPlayable -> item.id
        else -> null
    }

    /** The first trailer the server lists, from its start. Web trailers are already left out (parseTrailers). */
    fun trailer(trailers: List<Item>): PreviewClip? =
        trailers.firstOrNull()?.let { PreviewClip(it.id, it.mediaSourceId, 0, null) }

    /**
     * The title's own opening, for when it has no trailer: from the end of its
     * intro, else 90 seconds in, stepping past any marked stretch it lands in
     * (a recap of earlier episodes) and stopping at the next one, after 90
     * seconds, or at a tenth of the runtime, whichever comes first. Null for
     * a show (no file of its own), an unknown length, or a title too short to
     * have a safe stretch: never a frame past the tenth.
     */
    fun opening(item: Item, segments: List<Segment>): PreviewClip? {
        if (!item.isPlayable) return null
        val runtime = (item.runtimeTicks ?: return null) * 1000 / TICKS_PER_SECOND
        val marks = segments.map { (it.startSeconds * 1000).toLong() to (it.endSeconds * 1000).toLong() }.filter { it.second > it.first }
        val introEnd = segments.filter { it.type.equals("Intro", true) && it.endSeconds > it.startSeconds }
            .minByOrNull { it.startSeconds }?.let { (it.endSeconds * 1000).toLong() }
        return listOfNotNull(introEnd, OPENING_MS).firstNotNullOfOrNull { from -> stretch(from, marks, runtime / 10) }
            ?.let { (start, end) -> PreviewClip(item.id, item.mediaSourceId, start, end) }
    }

    private fun stretch(from: Long, marks: List<Pair<Long, Long>>, limit: Long): Pair<Long, Long>? {
        var start = from
        while (true) start = marks.firstOrNull { start >= it.first && start < it.second }?.second ?: break
        val next = marks.filter { it.first > start }.minOfOrNull { it.first } ?: Long.MAX_VALUE
        val end = minOf(limit, start + LONGEST_MS, next)
        return if (end - start >= SHORTEST_MS) start to end else null
    }
}
