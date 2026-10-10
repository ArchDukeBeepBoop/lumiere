package app.lumiere.android.player

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import app.lumiere.android.api.Item
import io.github.peerless2012.ass.media.kt.buildWithAssSupport
import app.lumiere.android.api.Server
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.UUID

@OptIn(UnstableApi::class)
object Playback {

    /**
     * A player whose every request goes through the signed-in client, with
     * libass drawing anime subtitles as they were styled — fonts, colours,
     * positions — into [subtitles]. [burnIn] draws them into the picture itself.
     */
    fun build(context: Context, server: Server, subtitles: androidx.media3.ui.SubtitleView, burnIn: Boolean): ExoPlayer {
        // Files on the phone as well as the server: a download plays from disk.
        val data = androidx.media3.datasource.DefaultDataSource.Factory(context, OkHttpDataSource.Factory(server.http))
        // Extension renderers preferred where present, for audio codecs the
        // platform decoders lack on some TVs (DTS, TrueHD fall back to them).
        val renderers = object : DefaultRenderersFactory(context) {
            // On a Quest, the sound leans towards the screen as you turn (ScreenAudio); elsewhere, as it was.
            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean) =
                if (!ScreenAudio.enabled) super.buildAudioSink(context, enableFloatOutput, enableAudioTrackPlaybackParams)
                else androidx.media3.exoplayer.audio.DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(enableFloatOutput)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf(ScreenAudio.Processor()))
                    .build()
        }
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)
        // OVERLAY is libass's own view laid over the picture; CANVAS draws into
        // each frame through Media3's effects pipeline — the burned-in look,
        // and heavier: on 10-bit HEVC that pipeline may not start at all.
        val type = if (burnIn) io.github.peerless2012.ass.media.type.AssRenderType.CANVAS
            else io.github.peerless2012.ass.media.type.AssRenderType.OVERLAY
        // Start sooner: one second of picture in hand rather than two and a
        // half, and a smaller buffer ahead, which a 2 GB device is glad of.
        val load = androidx.media3.exoplayer.DefaultLoadControl.Builder()
            // A shorter read-ahead where memory is short; more where it is not.
            .apply {
                // On a wire the read-ahead can be longer; on Wi-Fi a little shorter and steadier.
                if (app.lumiere.android.Device.lowMemory && app.lumiere.android.Device.wired) setBufferDurationsMs(15_000, 35_000, 1_000, 2_000)
                else if (app.lumiere.android.Device.lowMemory) setBufferDurationsMs(10_000, 25_000, 1_000, 2_000)
                else setBufferDurationsMs(15_000, 50_000, 1_000, 2_000)
            }
            .build()
        return ExoPlayer.Builder(context).setLoadControl(load).buildWithAssSupport(
            context, type, subtitles, data, androidx.media3.extractor.DefaultExtractorsFactory(), renderers,
        ).apply {
            // Subtitles in the system's language when there is a choice; the
            // controller's subtitle button changes it.
            trackSelectionParameters = trackSelectionParameters.buildUpon()
                .setPreferredTextLanguage(java.util.Locale.getDefault().language)
                .build()
        }
    }

    /**
     * The settings' track choices: subtitles on or off, and for an anime
     * library Japanese audio with English subtitles — the Mac's default.
     */
    fun applyTrackPrefs(player: ExoPlayer, subtitlesOn: Boolean, anime: Boolean, remembered: Pair<String?, String?>? = null, textLanguage: String? = null) {
        val b = player.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_TEXT, (!subtitlesOn && !anime) || remembered?.second == "off")
        textLanguage?.let { b.setPreferredTextLanguage(it) }
        if (anime) b.setPreferredAudioLanguage("ja").setPreferredTextLanguage("en")
        // The show's own languages chosen up front, so the first frame plays in them —
        // no switch a second in, which stalls a small box.
        remembered?.first?.let { b.setPreferredAudioLanguage(it) }
        remembered?.second?.takeIf { it != "off" }?.let { b.setPreferredTextLanguage(it).setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_TEXT, false) }
        player.trackSelectionParameters = b.build()
    }

    /** The file, its external subtitle files, and where to start. */
    fun load(player: ExoPlayer, server: Server, item: Item, startSeconds: Double, local: java.io.File? = null) {
        // Offline, the server's subtitle files cannot be fetched; the ones
        // inside the file still play.
        val external = if (local != null) emptyList() else item.streams.filter { it.type == "Subtitle" && it.isExternal }.map { stream ->
            MediaItem.SubtitleConfiguration.Builder(
                android.net.Uri.parse(server.subtitleUrl(item.id, item.mediaSourceId, stream.index, stream.codec))
            )
                .setMimeType(when (stream.codec?.lowercase()) {
                    "ass", "ssa" -> MimeTypes.TEXT_SSA
                    "vtt", "webvtt" -> MimeTypes.TEXT_VTT
                    else -> MimeTypes.APPLICATION_SUBRIP
                })
                .setLanguage(stream.language)
                .setLabel(listOfNotNull(stream.title?.takeIf { it.isNotBlank() }, "beside the file").joinToString(" · "))
                .build()
        }
        val media = MediaItem.Builder()
            .setUri(local?.let { android.net.Uri.fromFile(it) } ?: android.net.Uri.parse(server.streamUrl(item.id, item.mediaSourceId)))
            .setMediaId(item.id)
            .setSubtitleConfigurations(external)
            .build()
        player.setMediaItem(media, (startSeconds * 1000).toLong().coerceAtLeast(0))
        player.prepare()
        player.playWhenReady = true
    }

    /** A playback failure in words: what the TV could not do, not an error code. */
    fun explain(e: androidx.media3.common.PlaybackException): String = when (e.errorCode) {
        androidx.media3.common.PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
        androidx.media3.common.PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        androidx.media3.common.PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES ->
            "This device can't decode this file's video or audio. It plays on the Mac; a lighter copy would play here."
        androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
        androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ->
            "Lost the server. Is the Mac awake and on the same Wi-Fi?"
        androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ->
            "The server refused the file — try signing out and in again."
        androidx.media3.common.PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSOR_INIT_FAILED,
        androidx.media3.common.PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED ->
            "Burned-in subtitles can't be drawn into this video here. Turn off \"Burn anime subtitles into the picture\" in Settings."
        else -> "Couldn't play this: ${e.errorCodeName.removePrefix("ERROR_CODE_").lowercase().replace('_', ' ')}."
    }

    /**
     * The file with its audio converted to AAC on the Mac, from [start]
     * seconds. Its subtitles come inside it, so the server's separate
     * subtitle files — timed from zero — are left out.
     */
    fun loadConverted(player: ExoPlayer, server: Server, item: Item, start: Double, audioIndex: Int?) {
        val url = server.url("Videos/${item.id}/aac.mkv",
            mapOf("start" to "%.3f".format(java.util.Locale.ROOT, start), "audio" to audioIndex?.toString()))
        player.setMediaItem(MediaItem.Builder().setUri(url.toString()).setMediaId(item.id).build())
        player.prepare()
        player.playWhenReady = true
    }

    /** Readies [next] ahead of time: its details, previews, and the start of its file read from the Mac's disk. */
    suspend fun warm(server: Server, userId: String, next: Item) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        runCatching { server.item(userId, next.id) }
        runCatching {
            server.http.newCall(okhttp3.Request.Builder().url(server.streamUrl(next.id, next.mediaSourceId))
                .header("Range", "bytes=0-4194303").build()).execute().use { it.body?.bytes() }
        }
    }

    fun onEnded(player: ExoPlayer, action: () -> Unit): Player.Listener {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) action()
            }
        }
        player.addListener(listener)
        return listener
    }

    /** The episode after this one, across a season boundary; null at the end. */
    /** Videos queued by "Play All" in a folder, played in turn after the one on screen. */
    var queue: List<Item> = emptyList()

    suspend fun nextEpisode(server: Server, userId: String, item: Item): Item? {
        queue.indexOfFirst { it.id == item.id }.takeIf { it >= 0 }?.let { return queue.getOrNull(it + 1) }
        val series = item.seriesId ?: return null
        if (!item.isEpisode) return null
        val all = runCatching { server.episodes(userId, series, null) }.getOrDefault(emptyList())
        val here = all.indexOfFirst { it.id == item.id }
        return if (here >= 0) all.getOrNull(here + 1) else null
    }
}

/**
 * Start, progress and stop, to /Sessions/Playing. Stopped carries the resume
 * point, which is the report that matters; the server marks the title
 * watched itself once past its watched point.
 */
class Reporter(private val server: Server, var itemId: String, private val scope: CoroutineScope,
               private val clock: () -> Clock?) {
    private val session = UUID.randomUUID().toString().replace("-", "")
    private var stopped = false

    private fun ticks(player: ExoPlayer) = clock()?.let { (it.now() * 10_000_000).toLong() }
        ?: (player.currentPosition.coerceAtLeast(0) * 10_000)

    fun started(player: ExoPlayer) = scope.launch {
        server.report("Sessions/Playing", itemId, ticks(player), session, false)
    }

    fun progress(player: ExoPlayer) = scope.launch {
        server.report("Sessions/Playing/Progress", itemId, ticks(player), session, !player.isPlaying)
    }

    fun stopped(player: ExoPlayer, finished: Boolean) {
        if (stopped) return
        stopped = true
        val position = if (finished) ((clock()?.duration() ?: (player.duration / 1000.0)) * 10_000_000).toLong() else ticks(player)
        // Its own scope: the screen's is being torn down as this runs, and
        // this is the one report that must arrive.
        CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            server.report("Sessions/Playing/Stopped", itemId, position, session, false)
            if (finished) runCatching { server.setPlayed(itemId, true) }
        }
    }
}

/**
 * Where playback is, in the file's own time. Usually the player's position;
 * for audio converted on the server the stream starts wherever it was asked
 * to, so seeking asks again from the new point and the offset is added here.
 */
class Clock(val player: ExoPlayer) {
    var offset = 0.0
    var runtime = 0.0
    /** Set when converting: reloads the stream from a point, in seconds. */
    var restartAt: ((Double) -> Unit)? = null

    fun now(): Double = offset + player.currentPosition.coerceAtLeast(0) / 1000.0
    fun duration(): Double = if (restartAt != null) runtime
        else (player.duration.takeIf { it > 0 } ?: 0L) / 1000.0

    fun seek(seconds: Double) {
        val to = seconds.coerceIn(0.0, duration().takeIf { it > 0 } ?: Double.MAX_VALUE)
        val restart = restartAt
        if (restart != null) { offset = to; restart(to) } else player.seekTo((to * 1000).toLong())
    }
}
