package app.lumiere.android.player

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.unit.sp
import app.lumiere.android.ui.Symbols
import androidx.compose.animation.core.tween
import androidx.compose.ui.draw.alpha
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.LTextButton
import app.lumiere.android.ui.LChip
import app.lumiere.android.ui.LIconButton

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Subtitles
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.exoplayer.ExoPlayer
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.Trickplay
import app.lumiere.android.api.trickplaySheet
import app.lumiere.android.music.clock
import app.lumiere.android.ui.Palette
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * The player's own controls, drawn over the picture. A tap shows or hides
 * them; a double tap on either half skips ten seconds; a slide up or down
 * on the left sets brightness and on the right volume. On a TV the remote's
 * left and right skip, and OK shows the controls.
 */
@Composable
fun PlayerOverlay(
    player: ExoPlayer, clock: Clock, item: Item?, server: Server, trickplay: Trickplay?, isTv: Boolean, inPip: Boolean,
    hasNext: Boolean, onBack: () -> Unit, onTracks: () -> Unit, onPip: () -> Unit, onNext: () -> Unit,
    onMenu: () -> Unit = {},
    /** The TV bar's Subtitles and Audio buttons. */
    onSubtitles: () -> Unit = onTracks,
    onAudio: () -> Unit = onTracks,
    onEpisodes: (() -> Unit)? = null,
    /** Play/Pause held: the chapters, to jump between. */
    onChapters: (() -> Unit)? = null,
    error: String? = null,
    /** A sheet or panel is open on top: the controls keep their hands off the remote. */
    modal: Boolean = false,
    /** Skip Intro or Up Next has the remote for now. */
    offering: Boolean = false,
    /** The TV's tabs show under the transport, which rises above them and stays. */
    tabsOpen: Boolean = false,
    /** The TV's transport shows or hides, so the subtitles can step above it. */
    onChrome: (Boolean) -> Unit = {},
    /** The TV's pause screen shows or goes. */
    onResting: (Boolean) -> Unit = {},
    /** Where subtitles sit, and moving them: two fingers up or down on a phone. */
    lift: () -> Float = { 0.06f },
    onLift: (Float) -> Unit = {},
) {
    if (inPip) return
    val context = LocalContext.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    var visible by remember { mutableStateOf(true) }
    var touched by remember { mutableIntStateOf(0) }
    var position by remember { mutableFloatStateOf(0f) }
    var duration by remember { mutableFloatStateOf(0f) }
    var playing by remember { mutableStateOf(true) }
    var scrubbing by remember { mutableStateOf<Float?>(null) }
    var flash by remember { mutableStateOf<String?>(null) }
    val playFocus = remember { FocusRequester() }
    val rootFocus = remember { FocusRequester() }

    LaunchedEffect(player) {
        while (true) {
            if (scrubbing == null) position = clock.now().toFloat()
            duration = clock.duration().toFloat()
            playing = player.isPlaying
            delay(250)
        }
    }
    // The TV's transport (TV_PLAYER_PLAN §4–5): -1 is the bar, 0 and up a button.
    var zone by remember { mutableIntStateOf(-1) }
    var scrubFrom by remember { mutableFloatStateOf(0f) }
    var wasPlaying by remember { mutableStateOf(true) }
    var mark by remember { mutableStateOf<Pair<androidx.compose.ui.graphics.vector.ImageVector?, String>?>(null) }
    var backHeld by remember { mutableStateOf(false) }
    // Apple's pause screen: paused and left alone for 6 s, the picture dims and says what it is.
    var resting by remember { mutableStateOf(false) }
    LaunchedEffect(resting) { onResting(resting) }
    LaunchedEffect(playing, touched, scrubbing, modal) {
        resting = false
        if (isTv && !playing && scrubbing == null && !modal) { delay(6000); resting = true; visible = false }
    }
    LaunchedEffect(mark) { if (mark != null) { delay(900); mark = null } }
    LaunchedEffect(visible) { if (!visible) zone = -1 }
    LaunchedEffect(visible || scrubbing != null) { onChrome(visible || scrubbing != null) }
    LaunchedEffect(visible, touched, scrubbing, playing, zone, tabsOpen) {
        if (visible && scrubbing == null && playing && zone < 0 && !tabsOpen) { delay(if (isTv) 5000 else 4000); visible = false }
    }
    LaunchedEffect(visible, modal, offering) {
        if (offering) return@LaunchedEffect
        // Back from a sheet: the remote returns to the controls. On a TV the remote
        // always rests on the whole player; the bar and buttons are steered by hand.
        if (!modal) runCatching { if (visible && !isTv) playFocus.requestFocus() else rootFocus.requestFocus() }
    }
    LaunchedEffect(flash) { if (flash != null) { delay(700); flash = null } }
    // Back closes the controls first, then leaves.
    // On a TV a stray Back never ends the film: with the controls hidden it shows them;
    // a second Back, with them up, leaves. (Elsewhere Back closes the controls first.)
    androidx.activity.compose.BackHandler(enabled = !isTv && !modal && visible && playing) { visible = false }
    // Play or pause: the glyph flashes in the middle, as tvOS confirms it.
    var glyph by remember { mutableStateOf<Boolean?>(null) }
    var firstPlay by remember { mutableStateOf(true) }
    LaunchedEffect(playing) { if (firstPlay) { firstPlay = false; return@LaunchedEffect }; glyph = playing; delay(600); glyph = null }
    // Holding left or right on a remote: the target moves, faster the longer
    // it is held, with the preview showing; the jump happens on letting go.
    var held by remember { mutableStateOf<Float?>(null) }
    // Left and right skip while the play button has focus — the button the
    // controls open on — as on Netflix and YouTube; up and down reach the rest.
    var playFocused by remember { mutableStateOf(false) }
    fun seekBy(seconds: Int) {
        clock.seek(clock.now() + seconds)
        if (isTv) mark = (if (seconds > 0) Symbols.skipForward else Symbols.skipBack) to (if (seconds > 0) "+$seconds" else "−${-seconds}")
        else flash = if (seconds > 0) "+${seconds}s" else "${seconds}s"
    }
    val buttons = buildList {
        add(BarButton(Symbols.subtitles, "Subtitles", onSubtitles))
        add(BarButton(Symbols.audio, "Audio", onAudio))
        add(BarButton(Symbols.more, "More", onMenu))
        if (hasNext) add(BarButton(Symbols.next, "Next Episode", onNext))
        // The Quest's room adds its own (the wall mount) while a film is on its screen.
        Theater.barButton?.takeIf { Theater.active }?.let { (label, act) -> add(BarButton(Symbols.picture, label, act)) }
    }
    fun toggle() { if (player.isPlaying) player.pause() else player.play() }
    fun commitScrub() { scrubbing?.let { clock.seek(it.toDouble()) }; scrubbing = null; player.play() }
    fun cancelScrub() { scrubbing = null; if (wasPlaying) player.play() }
    fun scrubBy(right: Boolean, repeat: Int) {
        if (scrubbing == null) { wasPlaying = player.isPlaying; player.pause(); scrubFrom = clock.now().toFloat() }
        val step = TvRemote.step(repeat)
        scrubbing = ((scrubbing ?: scrubFrom) + if (right) step else -step).coerceIn(0f, duration)
        visible = true
    }
    /** The TV remote, state by state (TV_PLAYER_PLAN §5). */
    fun tvKey(k: KeyEvent): Boolean {
        val code = k.keyCode
        // Any press wakes the pause screen to the transport, and does nothing else.
        if (resting) {
            if (k.action == KeyEvent.ACTION_UP || (code == KeyEvent.KEYCODE_BACK && k.action == KeyEvent.ACTION_DOWN)) {
                if (k.action == KeyEvent.ACTION_UP) { resting = false; visible = true; touched++ }
                return true
            }
            return true
        }
        if (code == KeyEvent.KEYCODE_BACK) {
            if (k.action == KeyEvent.ACTION_DOWN) {
                // Held: always leave.
                if (k.repeatCount >= 2 && !backHeld) { backHeld = true; onBack() }
                return true
            }
            if (k.action != KeyEvent.ACTION_UP) return true
            if (backHeld) { backHeld = false; return true }
            touched++
            when (val act = TvRemote.back(TvRemote.At(visible, zone, scrubbing != null, buttons.size))) {
                TvRemote.Act.Cancel -> cancelScrub()
                is TvRemote.Act.Zone -> zone = act.zone
                TvRemote.Act.Show -> visible = true
                else -> onBack()
            }
            return true
        }
        if (k.action != KeyEvent.ACTION_DOWN) return false
        touched++
        // Play/Pause held: undo the pause the press began with, and show the chapters.
        if (k.repeatCount == 3 && onChapters != null && code == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) { player.play(); onChapters(); return true }
        TvRemote.down(code, k.repeatCount, TvRemote.At(visible, zone, scrubbing != null, buttons.size))?.let { act ->
            when (act) {
                TvRemote.Act.Show -> visible = true
                TvRemote.Act.PauseAndShow -> { player.pause(); visible = true }
                TvRemote.Act.Toggle -> toggle()
                TvRemote.Act.ToggleAndShow -> { toggle(); visible = true }
                is TvRemote.Act.Press -> buttons.getOrNull(act.button)?.action?.invoke()
                TvRemote.Act.Commit -> commitScrub()
                TvRemote.Act.Cancel -> cancelScrub()
                is TvRemote.Act.Scrub -> scrubBy(act.forward, k.repeatCount)
                is TvRemote.Act.Skip -> { seekBy(act.seconds); visible = true }
                is TvRemote.Act.Zone -> zone = act.zone
                TvRemote.Act.Leave -> onBack()
                TvRemote.Act.Tabs -> onTracks()
                TvRemote.Act.Menu -> onMenu()
                TvRemote.Act.Nothing -> Unit
            }
            return true
        }
        return when (code) {
            KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_CHANNEL_UP -> {
                val at = clock.now()
                item?.chapters?.firstOrNull { it.startSeconds > at + 1 }?.let { clock.seek(it.startSeconds); mark = Symbols.next to (it.name ?: "Next chapter"); visible = true }
                true
            }
            KeyEvent.KEYCODE_MEDIA_PREVIOUS, KeyEvent.KEYCODE_CHANNEL_DOWN -> {
                val at = clock.now()
                item?.chapters?.lastOrNull { it.startSeconds < at - 3 }?.let { clock.seek(it.startSeconds); mark = Symbols.previous to (it.name ?: "Previous chapter"); visible = true }
                true
            }
            // Number keys: 1–9 jump to that tenth of the film, 0 to the start.
            in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> {
                val n = code - KeyEvent.KEYCODE_0
                if (duration > 0) { clock.seek(duration * n / 10.0); mark = null to (if (n == 0) "Start" else "${n * 10} %"); visible = true }
                true
            }
            KeyEvent.KEYCODE_PROG_RED -> { onEpisodes?.invoke(); onEpisodes != null }
            else -> false
        }
    }

    Box(
        Modifier.fillMaxSize()
            .focusRequester(rootFocus)
            .focusable()
            .onPreviewKeyEvent { e ->
                if (modal) return@onPreviewKeyEvent false
                if (isTv) return@onPreviewKeyEvent tvKey(e.nativeKeyEvent)
                val code = e.nativeKeyEvent.keyCode
                val seeking = code == KeyEvent.KEYCODE_DPAD_LEFT || code == KeyEvent.KEYCODE_DPAD_RIGHT
                if (e.nativeKeyEvent.action == KeyEvent.ACTION_UP) {
                    if (seeking && held != null) {
                        val from = clock.now().toFloat()
                        flash = (held!! - from).toInt().let { if (it >= 0) "+${it}s" else "${it}s" }
                        clock.seek(held!!.toDouble()); held = null; scrubbing = null
                        return@onPreviewKeyEvent true
                    }
                    return@onPreviewKeyEvent false
                }
                if (e.nativeKeyEvent.action != KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                touched++
                when (code) {
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> if (!visible || held != null || (isTv && playFocused)) {
                        val repeat = e.nativeKeyEvent.repeatCount
                        val step = (10f * (1 + repeat / 4)).coerceAtMost(120f)
                        val from = held ?: clock.now().toFloat()
                        val to = (from + if (code == KeyEvent.KEYCODE_DPAD_RIGHT) step else -step).coerceIn(0f, duration)
                        held = to; scrubbing = to
                        true
                    } else false
                    KeyEvent.KEYCODE_DPAD_DOWN -> when {
                        !visible -> { onTracks(); true }
                        // Down from the play button: the season's episodes.
                        isTv && playFocused && onEpisodes != null -> { onEpisodes(); true }
                        else -> false
                    }
                    KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_SETTINGS -> { onMenu(); true }
                    // Number keys: 1–9 jump to that tenth of the film, 0 to the start.
                    in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> {
                        val n = code - KeyEvent.KEYCODE_0
                        if (duration > 0) { clock.seek(duration * n / 10.0); flash = if (n == 0) "Start" else "${n * 10}%" }
                        true
                    }
                    // The red button: the season's episodes.
                    KeyEvent.KEYCODE_PROG_RED -> { onEpisodes?.invoke(); onEpisodes != null }
                    // Next and previous, or channel up and down: by chapter.
                    KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_CHANNEL_UP -> {
                        val at = clock.now()
                        item?.chapters?.firstOrNull { it.startSeconds > at + 1 }?.let { clock.seek(it.startSeconds); flash = it.name ?: "Next chapter" }
                        true
                    }
                    KeyEvent.KEYCODE_MEDIA_PREVIOUS, KeyEvent.KEYCODE_CHANNEL_DOWN -> {
                        val at = clock.now()
                        item?.chapters?.lastOrNull { it.startSeconds < at - 3 }?.let { clock.seek(it.startSeconds); flash = it.name ?: "Previous chapter" }
                        true
                    }
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                        val r = e.nativeKeyEvent.repeatCount
                        if (r == 0) { if (player.isPlaying) player.pause() else player.play() }
                        // Held: undo the pause the press began with, and show the chapters.
                        else if (r == 3 && onChapters != null) { player.play(); onChapters() }
                        true
                    }
                    KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { seekBy(30); true }
                    KeyEvent.KEYCODE_MEDIA_REWIND -> { seekBy(-30); true }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_UP ->
                        if (!visible) { visible = true; true } else false
                    else -> false
                }
            }
            // A Quest has the TV's layout and a pointer: a tap on the picture shows the controls there too.
            .then(if (isTv && !app.lumiere.android.Flavor.quest) Modifier
                else Modifier.gestures(context, onTap = { visible = !visible }, onSeek = ::seekBy, lift, onLift)),
    ) {
        error?.let {
            Text(it, color = Color.White, style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                modifier = Modifier.align(Alignment.Center).padding(top = 200.dp, start = 32.dp, end = 32.dp)
                    .background(Color.Black.copy(alpha = 0.85f), RoundedCornerShape(12.dp)).padding(20.dp))
        }
        if (!visible && held != null) {
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(24.dp)) {
                BoxWithConstraints(Modifier.fillMaxWidth().height(160.dp)) {
                    val t = trickplay
                    if (t != null && duration > 0) ScrubPreview(server, item?.id ?: "", t, held!!, (held!! / duration) * maxWidth.value)
                    else Text(clock(held!!.toDouble()), color = Color.White, modifier = Modifier.align(Alignment.BottomCenter))
                }
                androidx.compose.material3.LinearProgressIndicator(progress = { if (duration > 0) held!! / duration else 0f },
                    color = if (isTv) Color.White else Palette.accent, trackColor = Color.White.copy(alpha = 0.3f), modifier = Modifier.fillMaxWidth())
            }
        }
        flash?.let {
            Text(it, color = Color.White, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge,
                modifier = Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 18.dp, vertical = 8.dp))
        }
        if (isTv) {
            AnimatedVisibility(resting, enter = fadeIn(tween(app.lumiere.android.Motion.ms(600))), exit = fadeOut(tween(app.lumiere.android.Motion.ms(200)))) {
                PauseScreen(item)
            }
            AnimatedVisibility(visible || scrubbing != null, enter = fadeIn(tween(app.lumiere.android.Motion.ms(200))) +
                    androidx.compose.animation.slideInVertically(tween(app.lumiere.android.Motion.ms(200))) { (12 * density.density).toInt() },
                exit = fadeOut(tween(app.lumiere.android.Motion.ms(300)))) {
                TvTransport(item, server, trickplay, BarState(position, duration, position + (player.bufferedPosition - player.currentPosition).coerceAtLeast(0) / 1000f, playing, scrubbing,
                    zone, mark, player.playbackParameters.speed), buttons, lift = if (tabsOpen) TabsHeight else 0.dp)
            }
            return@Box
        }
        AnimatedVisibility(visible, enter = fadeIn(), exit = fadeOut()) {
            // A phone's and the Quest's controls are the iPhone player's: see PhoneChrome.
            PhoneChrome(item, server, trickplay, playing, position, duration, scrubbing, hasNext,
                onScrub = { scrubbing = it; touched++ }, onSeek = { clock.seek(it.toDouble()); scrubbing = null },
                onSkip = { seekBy(it); touched++ }, onToggle = { if (player.isPlaying) player.pause() else player.play(); touched++ },
                onBack = onBack, onTracks = onTracks, onMenu = onMenu, onPip = onPip, onNext = onNext, onEpisodes = onEpisodes)
        }
    }
}

/** The chapter's name at a point, where chapters have names. */
internal fun chapterAt(item: Item?, seconds: Float): String? =
    item?.chapters?.lastOrNull { it.startSeconds <= seconds }?.name?.takeIf { it.isNotBlank() && !it.startsWith("Chapter") }

/** Small ticks along the bar where chapters begin. */
@Composable
internal fun ChapterMarks(item: Item?, duration: Float) {
    val chapters = item?.chapters?.filter { it.startSeconds > 1 } ?: return
    if (duration <= 0 || chapters.isEmpty()) return
    BoxWithConstraints(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 10.dp)) {
        chapters.forEach { c ->
            Box(Modifier.align(Alignment.CenterStart).offset(x = maxWidth * (c.startSeconds.toFloat() / duration))
                .width(2.dp).height(10.dp).background(Color.White.copy(alpha = 0.7f)))
        }
    }
}

/**
 * The frames at the scrub point, cut from the server's tile sheets, above the
 * bar: the one there, and dimmer ones either side, as tvOS shows a strip.
 */
@Composable
internal fun ScrubPreview(server: Server, id: String, t: Trickplay, seconds: Float, x: Float) {
    val index = ((seconds * 1000) / t.intervalMs).toInt().coerceIn(0, (t.count - 1).coerceAtLeast(0))
    val w = 192.dp
    val h = w * (t.height.toFloat() / t.width)
    val side = w * 0.7f
    val sideH = h * 0.7f
    Column(Modifier.offset(x = (x.dp - w / 2 - side - 8.dp).coerceAtLeast(0.dp), y = -(h + 30.dp)),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (index > 0) Tile(server, id, t, index - 1, side, sideH, 0.55f) else Spacer(Modifier.width(side))
            Tile(server, id, t, index, w, h, 1f)
            if (index < t.count - 1) Tile(server, id, t, index + 1, side, sideH, 0.55f) else Spacer(Modifier.width(side))
        }
        Spacer(Modifier.height(2.dp))
        Text(clock(seconds.toDouble()), color = Color.White)
    }
}

@Composable
internal fun Tile(server: Server, id: String, t: Trickplay, index: Int, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp, alpha: Float) {
    val perSheet = t.tiles * t.tiles
    val sheet = index / perSheet
    val cell = index % perSheet
    Box(Modifier.size(w, h).clip(RoundedCornerShape(6.dp)).background(Color.Black).alpha(alpha)) {
        AsyncImage(server.trickplaySheet(id, t.width, sheet), null, contentScale = ContentScale.FillBounds,
            modifier = Modifier.wrapContentSize(Alignment.TopStart, unbounded = true)
                .requiredSize(w * t.tiles, h * t.tiles)
                .offset(x = -w * (cell % t.tiles), y = -h * (cell / t.tiles)))
    }
}

/** Phone gestures: tap, double tap to skip, slides for brightness and volume. */
private fun Modifier.gestures(context: Context, onTap: () -> Unit, onSeek: (Int) -> Unit,
                              lift: () -> Float, onLift: (Float) -> Unit): Modifier =
    this.pointerInput(Unit) {
        // Two fingers move the subtitles up or down; taken before the one-finger gestures see it.
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            var level = lift()
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val down = event.changes.filter { it.pressed }
                if (down.size >= 2) {
                    val dy = down.map { it.position.y - it.previousPosition.y }.average().toFloat()
                    level = (level - dy / size.height).coerceIn(0f, 0.6f)
                    onLift(level)
                    event.changes.forEach { it.consume() }
                }
            } while (event.changes.any { it.pressed })
        }
    }.pointerInput(Unit) {
        detectTapGestures(
            onTap = { onTap() },
            onDoubleTap = { p -> onSeek(if (p.x < size.width / 2) -10 else 10) },
        )
    }.pointerInput(Unit) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        var left = true
        var level = 0f
        detectVerticalDragGestures(
            onDragStart = { p ->
                left = p.x < size.width / 2
                level = if (left) brightness(context) else
                    audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            },
        ) { _, drag ->
            level = (level - drag / size.height).coerceIn(0f, 1f)
            if (left) setBrightness(context, level)
            else audio.setStreamVolume(AudioManager.STREAM_MUSIC,
                (level * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt(), AudioManager.FLAG_SHOW_UI)
        }
    }

private fun brightness(context: Context): Float {
    val window = (context as? Activity)?.window ?: return 0.5f
    return window.attributes.screenBrightness.takeIf { it >= 0 } ?: 0.5f
}

/** For this window only; the phone's own setting is left alone and returns on leaving. */
private fun setBrightness(context: Context, level: Float) {
    val window = (context as? Activity)?.window ?: return
    window.attributes = window.attributes.apply { screenBrightness = level.coerceAtLeast(0.02f) }
}
