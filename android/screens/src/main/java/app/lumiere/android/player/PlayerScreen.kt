package app.lumiere.android.player

import app.lumiere.android.api.syncSubtitles
import app.lumiere.android.api.findSubtitle
import app.lumiere.android.is3D
import app.lumiere.android.api.itemJson
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.api.Item
import app.lumiere.android.api.Segment
import app.lumiere.android.Diagnostics
import app.lumiere.android.api.trickplay
import app.lumiere.android.ui.LocalFormFactor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Full-screen playback. The file is played as it is — the server never
 * transcodes — so ExoPlayer reads it directly over the home network, with
 * the token on every request.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(state: AppState, id: String, startSeconds: Double?) {
    val prefs = state.settings
    var askStillWatching by remember { mutableStateOf<Item?>(null) }
    var autoSkipped by remember { mutableStateOf<Segment?>(null) }
    val server = state.server ?: return
    val session = state.session ?: return
    val context = LocalContext.current
    @Suppress("DEPRECATION") val imageLoader = coil.compose.LocalImageLoader.current
    val scope = rememberCoroutineScope()
    val isTv = LocalFormFactor.current.isTv
    var item by remember { mutableStateOf<Item?>(null) }
    var segments by remember { mutableStateOf<List<Segment>>(emptyList()) }
    var position by remember { mutableStateOf(0.0) }
    var error by remember { mutableStateOf<String?>(null) }
    // The view first: libass draws into its subtitle layer, so the player is
    // built around it.
    val view = remember(id) {
        PlayerView(context).apply { keepScreenOn = true; useController = false }
    }
    val player = remember(id) {
        Playback.build(context, server, view.subtitleView!!, prefs.burnsInSubtitles).also { view.player = it }
    }
    val clock = remember(id) { Clock(player) }
    // The phone remote's hold on this title: seeking, skipping, tracks, and what it is told.
    androidx.compose.runtime.DisposableEffect(player, id) {
        fun streamsOf(type: String) = item?.streams.orEmpty().filter { it.type == type }
        fun chooseBy(index: Int, type: String, track: Int) {
            val lang = streamsOf(type).firstOrNull { it.index == index }?.language
            trackChoices(player, track).firstOrNull { it.language == lang }?.let { choose(player, it, track) }
        }
        app.lumiere.android.remote.RemoteHost.player = app.lumiere.android.remote.RemoteHost.PlayerHooks(
            seek = { clock.seek(it) },
            skip = { by -> clock.seek((clock.now() + by).coerceAtLeast(0.0)) },
            audio = { chooseBy(it, "Audio", androidx.media3.common.C.TRACK_TYPE_AUDIO) },
            subtitle = { i -> if (i < 0) choose(player, null, androidx.media3.common.C.TRACK_TYPE_TEXT)
                else chooseBy(i, "Subtitle", androidx.media3.common.C.TRACK_TYPE_TEXT) },
            state = {
                val cur = item
                val private = cur != null && (state.roomOpen || cur.libraryId in state.privateLibraries)
                val playingAudio = trackChoices(player, androidx.media3.common.C.TRACK_TYPE_AUDIO).firstOrNull { it.selected }?.language
                val playingText = trackChoices(player, androidx.media3.common.C.TRACK_TYPE_TEXT).firstOrNull { it.selected }?.language
                app.lumiere.android.remote.TvState(
                    itemId = cur?.id,
                    // From the private room the phone learns only that something plays.
                    title = if (private) "" else cur?.let { if (it.isEpisode) it.seriesName ?: it.name else it.name } ?: "",
                    subtitle = if (private) "" else cur?.takeIf { it.isEpisode }?.let { listOfNotNull(it.episodeLabel, it.name).joinToString(" · ") } ?: "",
                    isPrivate = private, position = clock.now(), duration = clock.duration(), playing = player.isPlaying,
                    audio = if (private) emptyList() else streamsOf("Audio").map { app.lumiere.android.remote.TvTrack(it.index, listOfNotNull(it.language?.uppercase(), it.title?.takeIf { t -> t.isNotBlank() }, if (it.isExternal) "beside the file" else null).joinToString(" · ").ifEmpty { "Track ${it.index}" }, it.language == playingAudio) },
                    subtitles = if (private) emptyList() else streamsOf("Subtitle").map { app.lumiere.android.remote.TvTrack(it.index, listOfNotNull(it.language?.uppercase(), it.title?.takeIf { t -> t.isNotBlank() }, if (it.isExternal) "beside the file" else null).joinToString(" · ").ifEmpty { "Track ${it.index}" }, playingText != null && it.language == playingText) },
                )
            },
        )
        onDispose { app.lumiere.android.remote.RemoteHost.player = null }
    }
    val sound = remember(id) { Sound() }
    var showPanel by remember { mutableStateOf(false) }
    var showEpisodes by remember { mutableStateOf(false) }
    var buffering by remember { mutableStateOf(true) }
    DisposableEffect(player) {
        val l = object : androidx.media3.common.Player.Listener {
            override fun onPlaybackStateChanged(s: Int) { buffering = s == androidx.media3.common.Player.STATE_BUFFERING || s == androidx.media3.common.Player.STATE_IDLE }
        }
        player.addListener(l)
        onDispose { player.removeListener(l) }
    }
    var upNextDismissed by remember(id) { mutableStateOf(false) }
    var skipLeft by remember { mutableStateOf(6) }
    val reporter = remember(id) { Reporter(server, id, scope) { clock } }
    LaunchedEffect(prefs.subtitleSize, prefs.subtitleStyle, prefs.fillsScreen, prefs.subtitleLift) { SubtitleStyle.apply(view, prefs) }
    // The next two episodes saved on the device while this one plays, when asked —
    // never from a private library.
    LaunchedEffect(item?.id) {
        val cur = item ?: return@LaunchedEffect
        if (!prefs.keepNextReady || !cur.isEpisode || cur.seriesId == null || state.roomOpen || cur.libraryId in state.privateLibraries) return@LaunchedEffect
        kotlinx.coroutines.delay(60_000)
        val eps = runCatching { server.episodes(session.userId, cur.seriesId!!, null) }.getOrDefault(emptyList())
        val at = eps.indexOfFirst { it.id == cur.id }
        if (at < 0) return@LaunchedEffect
        for (e in eps.drop(at + 1).take(2)) {
            if (state.downloads.find(e.id) != null) continue
            val json = runCatching { server.itemJson(session.userId, e.id) }.getOrNull() ?: continue
            if (!state.downloads.start(server, session.userId, json, prefs.downloadsWifiOnly)) break
        }
    }
    // A 3D film: a short word to switch the projector's 3D mode on.
    var threeD by remember { mutableStateOf(false) }
    LaunchedEffect(item?.id) { val i = item ?: return@LaunchedEffect
        if (isTv && !app.lumiere.android.AppBuild.quest && state.is3D(i)) { threeD = true; delay(6_000); threeD = false } }
    // A title played from outside a folder's Play All ends that queue.
    LaunchedEffect(item?.id) { val i = item ?: return@LaunchedEffect
        if (Playback.queue.none { it.id == i.id }) Playback.queue = emptyList() }
    // Started: it leaves the hand-made Up Next list (Continue Watching has it now).
    LaunchedEffect(item?.id) { val i = item ?: return@LaunchedEffect
        if (i.id in prefs.watchlist || i.seriesId in prefs.watchlist) prefs.watchlist = prefs.watchlist - i.id - (i.seriesId ?: "") }
    // Each show keeps its own subtitle size: set when one is opened, learned when changed.
    var sizeSeries by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(item?.seriesId) {
        val sid = item?.seriesId ?: return@LaunchedEffect
        prefs.subtitleSizeFor(sid)?.let { prefs.subtitleSize = it }
        sizeSeries = sid
    }
    LaunchedEffect(prefs.subtitleSize, sizeSeries) { sizeSeries?.let { prefs.rememberSubtitleSize(it, prefs.subtitleSize) } }
    // The same for fit or fill: a show filmed wide can keep Fill while films keep Fit.
    LaunchedEffect(item?.seriesId) { item?.seriesId?.let { sid -> prefs.fillFor(sid)?.let { prefs.fillsScreen = it } } }
    LaunchedEffect(prefs.fillsScreen, sizeSeries) { sizeSeries?.let { prefs.rememberFill(it, prefs.fillsScreen) } }
    // Each title comes up out of black once its first frame is drawn — no hard
    // cut from the last episode's frame, no flash of an empty surface.
    var firstFrame by remember(id) { mutableStateOf(false) }
    androidx.compose.runtime.DisposableEffect(player) {
        val l = object : androidx.media3.common.Player.Listener { override fun onRenderedFirstFrame() { firstFrame = true } }
        player.addListener(l)
        onDispose { player.removeListener(l) }
    }
    val veil by androidx.compose.animation.core.animateFloatAsState(if (firstFrame) 0f else 1f,
        androidx.compose.animation.core.tween(app.lumiere.android.Motion.ms(400)), label = "veil")
    val skipFocus = remember { FocusRequester() }
    var trickplay by remember { mutableStateOf<app.lumiere.android.api.Trickplay?>(null) }
    var showTracks by remember { mutableStateOf(false) }
    var showInfo by remember { mutableStateOf(false) }
    var subNote by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(item?.id) {
        val it = item ?: return@LaunchedEffect
        runCatching { app.lumiere.android.ui.Ambient.learn(context, app.lumiere.android.ui.imageFor(it, server, app.lumiere.android.ui.CardShape.Wide, 64)) }
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { app.lumiere.android.ui.Ambient.colour = null } }
    var infoTab by remember { mutableStateOf("Info") }
    var next by remember { mutableStateOf<Item?>(null) }
    // The Theater's transport offers Next too (on a Quest the window's own controls are out of sight).
    LaunchedEffect(next) { Theater.next = next?.let { n -> { state.pop(); state.push(Screen.Player(n.id, 0.0)) } } }
    val activity = context as? Activity

    ImmersiveLandscape(enabled = !isTv)
    if (!isTv) VideoSession(player, item, state)

    LaunchedEffect(id) {
        val local = state.downloads.playable(id)
        // Offline, a download carries its own copy of the item.
        runCatching { server.item(session.userId, id) }
            .recoverCatching { e -> state.downloads.find(id)?.item ?: throw e }
            // Asked to play a show or season — the spotlight's Play on a series:
            // its next episode, or the first when nothing is started.
            .mapCatching { found ->
                if (!found.isSeries && found.type != "Season") return@mapCatching found
                val series = if (found.isSeries) found.id else found.seriesId ?: found.id
                server.nextUp(session.userId).firstOrNull { it.seriesId == series }
                    ?.let { server.item(session.userId, it.id) }
                    ?: server.episodes(session.userId, series, if (found.isSeries) null else found.id).firstOrNull()
                        ?.let { server.item(session.userId, it.id) }
                    ?: error("This show has no episodes to play.")
            }
            .onSuccess { found ->
                item = found
                // What is actually playing — an episode when a show was asked for.
                reporter.itemId = found.id
                val anime = prefs.animeJapanese &&
                    state.views.firstOrNull { it.id == found.libraryId }?.name?.contains("anime", ignoreCase = true) == true
                Playback.applyTrackPrefs(player, prefs.subtitlesOn, anime, found.seriesId?.let { prefs.tracksFor(it) }, prefs.subtitleLanguage)
                val resumeAt = startSeconds ?: (found.positionTicks / 10_000_000.0)
                val video = found.streams.firstOrNull { it.type == "Video" }
                val audio = Compatibility.chooseAudio(found, anime, found.seriesId?.let { prefs.tracksFor(it)?.first })
                Diagnostics.note("play ${found.type}: video ${video?.codec} ${video?.width}x${video?.height} " +
                    "${video?.bitDepth ?: 8}-bit, audio ${audio?.codec}, ${found.streams.count { it.type == "Subtitle" }} subtitle tracks" +
                    if (local != null) ", from a download" else "")
                val problem = if (local == null) Compatibility.videoProblem(video, video?.width, video?.height, video?.bitDepth) else null
                if (problem != null) {
                    error = problem
                    Diagnostics.note("not played: $problem")
                    return@onSuccess
                }
                if (local == null && audio != null && !Compatibility.canDecodeAudio(audio.codec)) {
                    // Audio this device cannot decode: the Mac converts it to AAC
                    // and sends the picture as it is.
                    Diagnostics.note("audio ${audio.codec} converted on the server")
                    clock.runtime = (found.runtimeTicks ?: 0) / 10_000_000.0
                    clock.offset = resumeAt
                    clock.restartAt = { at -> Playback.loadConverted(player, server, found, at, audio.index) }
                    Playback.loadConverted(player, server, found, resumeAt, audio.index)
                } else {
                    Playback.load(player, server, found, resumeAt, local)
                }
                reporter.started(player)
                // After the file is asked for, not before: the skip marks are not
                // needed for the first seconds, and waiting on them delayed the picture.
                segments = server.segments(found.id)
                trickplay = if (local == null) server.trickplay(session.userId, found.id) else null
                next = Playback.nextEpisode(server, session.userId, found)
            }
            .onFailure { error = it.message ?: "Couldn't load this title." }
    }

    // Position for the skip offer, and progress every ten seconds.
    LaunchedEffect(player) {
        var tick = 0
        while (true) {
            delay(500)
            position = clock.now()
            if (++tick % 20 == 0) reporter.progress(player)
            if (tick % 4 == 0) {
                // Late at night, quieter peaks and clearer voices by themselves — Apple's Reduce Loud Sounds.
                val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                val night = prefs.nightAuto && (hour >= 22 || hour < 6)
                sound.apply(player.audioSessionId, if (night) maxOf(prefs.dialogueBoost, 3) else prefs.dialogueBoost, prefs.nightSound || night)
            }
            // The sleep timer's minutes: stop, keeping the place.
            SleepTimer.until?.let { if (System.currentTimeMillis() >= it) { SleepTimer.until = null; player.pause(); state.pop() } }
        }
    }

    // The show's remembered audio and subtitles, once the file's tracks are known.
    DisposableEffect(player) {
        val once = object : androidx.media3.common.Player.Listener {
            override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
                if (tracks.groups.isEmpty()) return
                player.removeListener(this)
                applyRemembered(player, prefs, item?.seriesId)
            }
        }
        player.addListener(once)
        // The film gets the memory: pictures held for the screens behind it go.
        @Suppress("DEPRECATION")
        runCatching { imageLoader.memoryCache?.clear() }
        // A file the TV cannot play said so, instead of a black screen.
        val failed = object : androidx.media3.common.Player.Listener {
            override fun onPlayerError(e: androidx.media3.common.PlaybackException) {
                error = Playback.explain(e)
                app.lumiere.android.Diagnostics.note("playback failed: ${e.errorCodeName} ${e.cause?.message}")
                // Sent to the Mac at once, so a failure never waits for someone to press a button.
                kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch { Diagnostics.send(server) }
            }
        }
        player.addListener(failed)
        // Which decoders the device chose, for the diagnostics log.
        val decoders = object : androidx.media3.exoplayer.analytics.AnalyticsListener {
            override fun onVideoDecoderInitialized(t: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime,
                                                   name: String, init: Long, duration: Long) =
                Diagnostics.note("video decoder $name")
            override fun onAudioDecoderInitialized(t: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime,
                                                   name: String, init: Long, duration: Long) =
                Diagnostics.note("audio decoder $name")
            override fun onDroppedVideoFrames(t: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime,
                                              dropped: Int, elapsed: Long) {
                if (dropped >= 10) Diagnostics.note("dropped $dropped frames in ${elapsed}ms")
            }
        }
        player.addAnalyticsListener(decoders)
        PictureInPicture.player = player
        onDispose {
            player.removeListener(once); player.removeListener(failed); player.removeAnalyticsListener(decoders)
            PictureInPicture.player = null; sound.release()
        }
    }

    DisposableEffect(player) {
        val ended = Playback.onEnded(player) {
            scope.launch {
                val current = item ?: return@launch
                val next = if (prefs.playsNext) Playback.nextEpisode(server, session.userId, current) else null
                reporter.stopped(player, finished = true)
                val limit = prefs.stillWatchingAfter
                when {
                    // "End of episode" on the sleep timer: stop here.
                    SleepTimer.endOfEpisode -> { SleepTimer.endOfEpisode = false; state.pop() }
                    next == null -> state.pop()
                    limit > 0 && state.autoStreak + 1 >= limit -> askStillWatching = next
                    else -> { state.pop(); state.push(Screen.Player(next.id, 0.0, auto = true)) }
                }
            }
        }
        onDispose {
            // Left partway, outside the room: the screensaver may offer it back.
            val here = item
            if (here != null && !state.roomOpen && here.libraryId !in state.privateLibraries && !player.playbackState.let { it == androidx.media3.common.Player.STATE_ENDED })
                app.lumiere.android.ui.Idle.leftOff = here
            player.removeListener(ended)
            reporter.stopped(player, finished = false)
            // The view lets go of the player and its last frame before the
            // player goes, so nothing frozen is left on screen after leaving.
            view.player = null
            player.clearVideoSurface()
            player.release()
        }
    }

    // In the credits, with the next episode offered, the film steps back into
    // a corner as Apple's player does. Sized, not scaled: a video surface
    // ignores scaling but follows its layout.
    var creditsCorner by remember { mutableStateOf(false) }
    val pictureSize by androidx.compose.animation.core.animateFloatAsState(if (creditsCorner && isTv) 0.42f else 1f,
        androidx.compose.animation.core.tween(app.lumiere.android.Motion.ms(450)), label = "credits")
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(factory = { view }, modifier = Modifier.align(Alignment.TopStart)
            .padding(start = (32 * (1 - pictureSize) / 0.58f).dp, top = (32 * (1 - pictureSize) / 0.58f).dp)
            .fillMaxSize(pictureSize))
        if (veil > 0f) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = veil)))
        // Picture tone: a faint warm or cool veil — the video surface itself
        // cannot be recoloured without the effects pipeline 10-bit files refuse.
        when (if (prefs.filmsWarm && item?.type == "Movie") 1 else prefs.pictureTone) {
            1 -> Box(Modifier.fillMaxSize().background(Color(0x14FF8A00)))
            2 -> Box(Modifier.fillMaxSize().background(Color(0x1200A0FF)))
        }
        LampBrightness(prefs.lampBright)
        PlayerOverlay(
            player, clock, item, server, trickplay, isTv, PictureInPicture.inPip, next != null,
            onBack = { state.pop() }, onTracks = { if (isTv) { infoTab = "Info"; showInfo = true } else showTracks = true },
            onChapters = if (isTv && !item?.chapters.isNullOrEmpty()) ({ infoTab = "Chapters"; showInfo = true }) else null,
            onPip = { activity?.let { PictureInPicture.enter(it) } },
            onNext = { next?.let { n -> state.pop(); state.push(Screen.Player(n.id, 0.0)) } },
            onMenu = { showPanel = true },
            onEpisodes = if (item?.isEpisode == true) ({ showEpisodes = true }) else null,
            error = error,
            modal = showPanel || showTracks || showInfo || showEpisodes || askStillWatching != null,
            lift = { prefs.subtitleLift }, onLift = { prefs.subtitleLift = it },
        )
        if (showEpisodes) item?.let { cur ->
            EpisodeStrip(server, session.userId, cur, onPick = { e -> state.pop(); state.push(Screen.Player(e.id, null)) },
                onClose = { showEpisodes = false })
        }
        if (showPanel) QuickPanel(player, prefs, onTracks = { showTracks = true }) { showPanel = false }
        if (showTracks) item?.let { cur ->
            val externals = cur.streams.count { it.type == "Subtitle" && it.isExternal }
            // A subtitle fetched or refitted is a new file: the title restarts where it was to load it.
            fun reload() { val at = clock.now(); state.pop(); state.push(Screen.Player(cur.id, at)) }
            TrackSheet(player, prefs, cur.seriesId, subNote,
                onFind = if (cur.streams.none { it.type == "Subtitle" }) ({
                    subNote = "Looking…"
                    scope.launch {
                        subNote = runCatching { server.findSubtitle(cur.id, prefs.subtitleLanguage) }
                            .fold({ r -> if (r == null) "None found" else { reload(); null } }, { "Couldn't: ${it.message}" })
                    }
                }) else null,
                onSync = if (externals > 0) ({
                    subNote = "Fitting to the dialogue… (a minute or two)"
                    scope.launch {
                        subNote = runCatching { server.syncSubtitles(cur) }.fold({ n -> if (n > 0) { reload(); null } else "Couldn't fit them" }, { "Couldn't: ${it.message}" })
                    }
                }) else null) { showTracks = false }
        } ?: TrackSheet(player, prefs, null) { showTracks = false }
        if (showInfo) InfoPanel(item, clock, infoTab, onTracks = { showTracks = true }, onMenu = { showPanel = true },
            onEpisodes = if (item?.isEpisode == true) ({ showEpisodes = true }) else null) { showInfo = false }
        if ((item == null || buffering) && error == null) CircularProgressIndicator(Modifier.align(Alignment.Center))
        // On a Quest the film leaves the window for the Theater's own screen (true 3D, 180°, 360°
        // there); otherwise the window's picture goes 3D itself, and a TV or projector is told to.
        val inTheater = rememberTheater(view, player, item, clock, server, item?.let { state.is3D(it) } ?: false,
            trickplay = { trickplay }, exit = { state.pop() })
        val stereo = item?.takeIf { !inTheater }
            ?.let { app.lumiere.android.api.stereoLayoutOf(it, state.is3D(it)) } ?: app.lumiere.android.api.StereoLayout.MONO
        val stereoSaid = rememberStereo(view, player, stereo)
        var stereoShown by remember(stereoSaid) { mutableStateOf(stereoSaid != null) }
        LaunchedEffect(stereoSaid) { delay(4_000); stereoShown = false }
        if (stereoShown) Text(if (stereoSaid == "3D") "Playing in 3D" else "This headset can't show 3D here, so it plays flat",
            color = Color.White,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 28.dp).background(Color.Black.copy(alpha = 0.7f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                .padding(horizontal = 18.dp, vertical = 8.dp))
        if (threeD) Text("3D film — turn on the projector's 3D mode (side by side)", color = Color.White,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 28.dp).background(Color.Black.copy(alpha = 0.7f), androidx.compose.foundation.shape.RoundedCornerShape(50))
                .padding(horizontal = 18.dp, vertical = 8.dp))

        val skip = segments.firstOrNull {
            it.type in setOf("Intro", "Recap", "Outro") && position >= it.startSeconds && position < it.endSeconds - 1
        }
        // Skipping by itself where asked to, once per mark — seeking back into
        // an intro on purpose is left alone.
        if (skip != null && prefs.skipsIntros && skip.type == "Intro" && autoSkipped != skip) {
            LaunchedEffect(skip) { autoSkipped = skip; clock.seek(skip.endSeconds) }
        }
        askStillWatching?.let { next ->
            StillWatching(
                onContinue = { state.pop(); state.push(Screen.Player(next.id, 0.0)) },
                onStop = { state.pop() },
            )
        }
        // The credits: Up Next with a countdown when there is a next episode,
        // otherwise the plain Skip Credits offer.
        val duration = clock.duration()
        val inCredits = next != null && duration > 0 &&
            (skip?.type == "Outro" || duration - position < 25)
        // Into the credits counts as watched, even if the player is left before the end.
        val creditsReached = duration > 0 && (skip?.type == "Outro" || duration - position < 25 || position / duration > 0.95)
        if (creditsReached && item != null) LaunchedEffect(item!!.id) { runCatching { server.setPlayed(item!!.id, true) } }
        // The credits: warm the next episode — its details, previews and the
        // first megabytes of its file — so it starts the moment it is asked for.
        if (inCredits && next != null) LaunchedEffect(next!!.id) { Playback.warm(server, session.userId, next!!) }
        val offered = inCredits && !upNextDismissed && askStillWatching == null
        // On a Quest, Up Next floats before you under the screen, and the film keeps the whole screen.
        val floating = app.lumiere.android.ui.Floating.enabled
        LaunchedEffect(offered) { creditsCorner = offered && !floating }
        if (floating) {
            LaunchedEffect(offered) { if (!offered) app.lumiere.android.ui.Floating.upNext = null }
            DisposableEffect(Unit) { onDispose { app.lumiere.android.ui.Floating.upNext = null } }
        }
        if (offered) {
            val playNext: () -> Unit = { val n = next!!; reporter.stopped(player, finished = true); state.pop(); state.push(Screen.Player(n.id, 0.0, auto = true)) }
            if (floating) LaunchedEffect(next!!.id) {
                app.lumiere.android.ui.Floating.upNext = app.lumiere.android.ui.Floating.UpNextOffer(next!!, server, prefs.playsNext,
                    onPlay = playNext, onDismiss = { upNextDismissed = true })
            }
            else UpNextCard(next!!, server, counting = prefs.playsNext, onPlay = playNext, onDismiss = { upNextDismissed = true })
        } else if (skip != null && !(prefs.skipsIntros && skip.type == "Intro")) {
            // On a TV an intro counts down and skips itself, unless Back says no.
            val counting = isTv && prefs.skipCountdown && skip.type == "Intro"
            if (counting) LaunchedEffect(skip) {
                skipLeft = 6
                // Counts only while the picture plays — a slow start used to spend
                // the whole countdown before the intro was even on screen.
                while (skipLeft > 0) { delay(1000); if (player.isPlaying) skipLeft-- }
                clock.seek(skip.endSeconds)
            }
            val skipLabel = (if (skip.type == "Outro") "Skip Credits" else "Skip ${skip.type}") + if (counting) " · $skipLeft" else ""
            if (app.lumiere.android.ui.Floating.enabled) {
                // On a Quest, it floats by you, under the screen, as Netflix's does over its picture.
                androidx.compose.runtime.SideEffect {
                    app.lumiere.android.ui.Floating.skip = app.lumiere.android.ui.Floating.SkipOffer(skipLabel) { clock.seek(skip.endSeconds) }
                }
                DisposableEffect(skip) { onDispose { app.lumiere.android.ui.Floating.skip = null } }
            } else {
                LButton(
                    onClick = { clock.seek(skip.endSeconds) },
                    // Above the seek bar, never under it.
                    modifier = Modifier.align(Alignment.BottomEnd).padding(end = 32.dp, bottom = 132.dp).focusRequester(skipFocus),
                ) { Text(skipLabel) }
                // On a TV, the offer takes focus so one press of OK skips.
                if (isTv) LaunchedEffect(skip) { runCatching { skipFocus.requestFocus() } }
            }
        }
    }
}

/** Landscape and edge-to-edge on a phone while the player is up. */
@Composable
private fun ImmersiveLandscape(enabled: Boolean) {
    val activity = LocalContext.current as? Activity ?: return
    DisposableEffect(enabled) {
        if (!enabled) return@DisposableEffect onDispose { }
        val previous = activity.requestedOrientation
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        onDispose {
            activity.requestedOrientation = previous
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }
}

/** Plex's question, after a run of episodes nobody touched. */
@Composable
private fun StillWatching(onContinue: () -> Unit, onStop: () -> Unit) {
    val focus = remember { FocusRequester() }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.8f)), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Still watching?", color = Color.White, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge)
            androidx.compose.foundation.layout.Row(Modifier.padding(top = 20.dp)) {
                LButton(onClick = onContinue, modifier = Modifier.focusRequester(focus)) { Text("Keep Watching") }
                app.lumiere.android.ui.LButton(primary = false, onClick = onStop, modifier = Modifier.padding(start = 12.dp)) {
                    Text("Stop")
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

/** Full brightness while a film plays, where Settings asks; the device's own level returns after. */
@Composable
private fun LampBrightness(on: Boolean) {
    val activity = LocalContext.current as? Activity ?: return
    DisposableEffect(on) {
        val window = activity.window
        val before = window.attributes.screenBrightness
        if (on) window.attributes = window.attributes.apply { screenBrightness = 1f }
        onDispose { window.attributes = window.attributes.apply { screenBrightness = before } }
    }
}
