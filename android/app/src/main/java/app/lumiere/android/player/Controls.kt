package app.lumiere.android.player

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
    onEpisodes: (() -> Unit)? = null,
    /** Play/Pause held: the chapters, to jump between. */
    onChapters: (() -> Unit)? = null,
    error: String? = null,
    /** A sheet or panel is open on top: the controls keep their hands off the remote. */
    modal: Boolean = false,
    /** Where subtitles sit, and moving them: two fingers up or down on a phone. */
    lift: () -> Float = { 0.06f },
    onLift: (Float) -> Unit = {},
) {
    if (inPip) return
    val context = LocalContext.current
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
    LaunchedEffect(visible, touched, scrubbing, playing) {
        if (visible && scrubbing == null && playing) { delay(4000); visible = false }
    }
    LaunchedEffect(visible, modal) {
        // Back from a sheet: the remote returns to the controls.
        if (!modal) runCatching { if (visible && isTv) playFocus.requestFocus() else rootFocus.requestFocus() }
    }
    LaunchedEffect(flash) { if (flash != null) { delay(700); flash = null } }
    // Back closes the controls first, then leaves.
    androidx.activity.compose.BackHandler(enabled = visible && playing && !modal) { visible = false }
    // Holding left or right on a remote: the target moves, faster the longer
    // it is held, with the preview showing; the jump happens on letting go.
    var held by remember { mutableStateOf<Float?>(null) }
    // Left and right skip while the play button has focus — the button the
    // controls open on — as on Netflix and YouTube; up and down reach the rest.
    var playFocused by remember { mutableStateOf(false) }
    fun seekBy(seconds: Int) {
        clock.seek(clock.now() + seconds)
        flash = if (seconds > 0) "+${seconds}s" else "${seconds}s"
    }

    Box(
        Modifier.fillMaxSize()
            .focusRequester(rootFocus)
            .focusable()
            .onPreviewKeyEvent { e ->
                if (modal) return@onPreviewKeyEvent false
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
            .then(if (isTv) Modifier else Modifier.gestures(context, onTap = { visible = !visible }, onSeek = ::seekBy, lift, onLift)),
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
                    color = Palette.accent, modifier = Modifier.fillMaxWidth())
            }
        }
        flash?.let {
            Text(it, color = Color.White, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge,
                modifier = Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 18.dp, vertical = 8.dp))
        }
        AnimatedVisibility(visible, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                0f to Color.Black.copy(alpha = 0.55f), 0.25f to Color.Transparent,
                0.65f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f)))) {
                Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    LIconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = app.lumiere.android.ui.pillTint(Color.White)) }
                    Column(Modifier.weight(1f)) {
                        Text(item?.seriesName ?: item?.name ?: "", color = Color.White,
                            style = androidx.compose.material3.MaterialTheme.typography.titleLarge, maxLines = 1)
                        if (item?.seriesName != null) Text(listOfNotNull(item.episodeLabel, item.name).joinToString(" · "),
                            color = Color.White.copy(alpha = 0.75f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        // Paused: what this is, as the pause screen on the Mac shows.
                        if (!playing) item?.overview?.let {
                            Text(it, color = Color.White.copy(alpha = 0.85f), maxLines = 4, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(top = 6.dp).fillMaxWidth(0.6f))
                        }
                    }
                    if (!playing) app.lumiere.android.ui.ClockText()
                    LIconButton(onClick = onTracks) { Icon(Icons.Default.Subtitles, "Audio and subtitles", tint = app.lumiere.android.ui.pillTint(Color.White)) }
                    LIconButton(onClick = onMenu) { Icon(Icons.Default.Tune, "Speed, picture and sound", tint = app.lumiere.android.ui.pillTint(Color.White)) }
                    if (!isTv) LIconButton(onClick = onPip) { Icon(Icons.Default.PictureInPictureAlt, "Picture in picture", tint = app.lumiere.android.ui.pillTint(Color.White)) }
                }
                Row(Modifier.align(Alignment.Center), horizontalArrangement = Arrangement.spacedBy(36.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    LIconButton(onClick = { seekBy(-10); touched++ }, Modifier.size(56.dp).focusProperties { canFocus = !isTv }) {
                        Icon(Icons.Default.Replay10, "Back ten seconds", tint = app.lumiere.android.ui.pillTint(Color.White), modifier = Modifier.size(36.dp))
                    }
                    LIconButton(onClick = { if (player.isPlaying) player.pause() else player.play(); touched++ },
                        Modifier.size(76.dp).focusRequester(playFocus).onFocusChanged { playFocused = it.isFocused }) {
                        Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play",
                            tint = app.lumiere.android.ui.pillTint(Color.White), modifier = Modifier.size(56.dp))
                    }
                    LIconButton(onClick = { seekBy(10); touched++ }, Modifier.size(56.dp).focusProperties { canFocus = !isTv }) {
                        Icon(Icons.Default.Forward10, "Forward ten seconds", tint = app.lumiere.android.ui.pillTint(Color.White), modifier = Modifier.size(36.dp))
                    }
                }
                Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp)) {
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        val shown = scrubbing ?: position
                        val trick = trickplay
                        if (scrubbing != null && trick != null && duration > 0) {
                            ScrubPreview(server, item?.id ?: "", trick, shown, (shown / duration) * maxWidth.value)
                        }
                        Column(Modifier.align(Alignment.BottomStart)) {
                            Box {
                                ChapterMarks(item, duration)
                                Slider(
                                    value = shown, valueRange = 0f..duration.coerceAtLeast(1f),
                                    onValueChange = { scrubbing = it; touched++ },
                                    onValueChangeFinished = { scrubbing?.let { clock.seek(it.toDouble()) }; scrubbing = null },
                                    colors = SliderDefaults.colors(thumbColor = Palette.accent, activeTrackColor = Palette.accent,
                                        inactiveTrackColor = Color.White.copy(alpha = 0.3f)),
                                )
                            }
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text("${clock(shown.toDouble())} / ${clock(duration.toDouble())}", color = Color.White,
                                    modifier = Modifier.weight(1f))
                                chapterAt(item, shown)?.let { Text(it, color = Color.White.copy(alpha = 0.8f), maxLines = 1) }
                                if (hasNext) LIconButton(onClick = onNext) { Icon(Icons.Default.SkipNext, "Next episode", tint = app.lumiere.android.ui.pillTint(Color.White)) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** The chapter's name at a point, where chapters have names. */
private fun chapterAt(item: Item?, seconds: Float): String? =
    item?.chapters?.lastOrNull { it.startSeconds <= seconds }?.name?.takeIf { it.isNotBlank() && !it.startsWith("Chapter") }

/** Small ticks along the bar where chapters begin. */
@Composable
private fun ChapterMarks(item: Item?, duration: Float) {
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
private fun ScrubPreview(server: Server, id: String, t: Trickplay, seconds: Float, x: Float) {
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
private fun Tile(server: Server, id: String, t: Trickplay, index: Int, w: androidx.compose.ui.unit.Dp, h: androidx.compose.ui.unit.Dp, alpha: Float) {
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
