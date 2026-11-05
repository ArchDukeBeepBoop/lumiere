package app.lumiere.android.player

import app.lumiere.android.ui.pointerTap

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.Trickplay
import app.lumiere.android.api.trickplaySheet
import app.lumiere.android.music.clock
import app.lumiere.android.ui.Symbols

/** One of the round buttons at the bar's right end. */
internal class BarButton(val symbol: ImageVector, val label: String, val action: () -> Unit)

/** What the bar shows: where the film is, where the remote is aiming, what has arrived. */
internal class BarState(
    val position: Float, val duration: Float, val buffered: Float, val playing: Boolean,
    /** The scrub target while scrubbing, else null. */
    val scrub: Float?,
    /** -1: the bar is chosen; 0 and up: that button is. */
    val zone: Int,
    /** A skip just made ("−10", "+10", a chapter's name) and which way, shown beside the playhead. */
    val mark: Pair<ImageVector?, String>?,
    val speed: Float,
)

private val digits = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum", color = Color.White.copy(alpha = 0.92f))

/**
 * The Apple TV player's transport (TV_PLAYER_PLAN §4): over a soft fall of shade
 * at the foot of the picture, the title at the left above a thin white bar, round
 * symbol buttons at its right, elapsed and remaining time under it. Nothing in
 * the middle of the picture. While scrubbing, the frame at the target rides
 * above the playhead and the picture dims.
 */
@Composable
internal fun TvTransport(item: Item?, server: Server, trickplay: Trickplay?, s: BarState, buttons: List<BarButton>, lift: Dp = 0.dp) {
    val shown = s.scrub ?: s.position
    Box(Modifier.fillMaxSize()) {
        if (s.scrub != null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
        // Shade deep enough for white type over a bright scene (checkpoint 1: a yellow coat washed it out).
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 0.72f to Color.Black.copy(alpha = 0.45f), 1f to Color.Black.copy(alpha = 0.85f))))
        Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = 56.dp, end = 56.dp, bottom = 34.dp + lift)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Column(Modifier.weight(1f)) {
                    item?.let { cur ->
                        Text(if (cur.isEpisode) cur.seriesName ?: cur.name else cur.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White))
                        if (cur.isEpisode) Text(listOfNotNull(cur.episodeLabel, cur.name).joinToString(" · "), maxLines = 1,
                            overflow = TextOverflow.Ellipsis, style = TextStyle(fontSize = 14.sp, color = Color.White.copy(alpha = 0.7f)))
                    }
                }
                // The chosen button names itself just above the row, as tvOS labels a focused symbol.
                Column(horizontalAlignment = Alignment.End) {
                    Text(buttons.getOrNull(s.zone)?.label ?: "", style = digits.copy(fontSize = 13.sp), modifier = Modifier.padding(bottom = 6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        // A pinch on a Quest presses a button directly; the remote moves along them (Pointer.kt).
                        buttons.forEachIndexed { i, b ->
                            Box(Modifier.then(Modifier.pointerTap(onClick = b.action))) { RoundButton(b.symbol, b.label, i == s.zone) }
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            Bar(item, server, trickplay, s, shown)
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(if (s.playing && s.scrub == null) Symbols.play else Symbols.pause, null, tint = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(6.dp))
                Text(clock(shown.toDouble()), style = digits)
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    chapterAt(item, shown)?.let { Text(it, style = digits.copy(color = Color.White.copy(alpha = 0.6f)), maxLines = 1) }
                }
                // "Ends at 10:42 PM" beside the time left, as Apple's player says it.
                if (s.duration > 0) Text("Ends at " + java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT)
                    .format(java.util.Date(System.currentTimeMillis() + ((s.duration - shown) * 1000 / s.speed.coerceAtLeast(0.1f)).toLong())),
                    style = digits.copy(color = Color.White.copy(alpha = 0.75f)))
                Spacer(Modifier.width(14.dp))
                Text("−" + clock((s.duration - shown).toDouble().coerceAtLeast(0.0)), style = digits)
            }
        }
    }
}

/** The bar itself: rounded, white for what has played, brighter grey for what has arrived, gaps at chapters. */
@Composable
private fun Bar(item: Item?, server: Server, trickplay: Trickplay?, s: BarState, shown: Float) {
    val chosen = s.zone == -1
    val thick by animateDpAsState(if (chosen || s.scrub != null) 10.dp else 6.dp, tween(app.lumiere.android.Motion.ms(150)), label = "bar")
    BoxWithConstraints(Modifier.fillMaxWidth().height(10.dp), contentAlignment = Alignment.CenterStart) {
        val w = maxWidth
        fun at(seconds: Float): Dp = if (s.duration > 0) w * (seconds / s.duration).coerceIn(0f, 1f) else 0.dp
        Box(Modifier.fillMaxWidth().height(thick).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.3f))) {
            Box(Modifier.width(at(s.buffered)).fillMaxHeight().background(Color.White.copy(alpha = 0.45f)))
            Box(Modifier.width(at(shown)).fillMaxHeight().background(Color.White))
            // Chapters: a 2 dp gap in the bar where each begins.
            item?.chapters?.filter { it.startSeconds > 1 }?.forEach { c ->
                Box(Modifier.offset(x = at(c.startSeconds.toFloat())).width(2.dp).fillMaxHeight().background(Color.Black.copy(alpha = 0.55f)))
            }
        }
        if (s.scrub != null) {
            // The playhead: a line through the bar, and the frame at the target above it.
            Box(Modifier.offset(x = at(shown) - 1.dp).wrapContentHeight(unbounded = true).width(2.dp).height(22.dp).background(Color.White, RoundedCornerShape(1.dp)))
            ScrubFrame(item, server, trickplay, shown, at(shown), w)
        }
        s.mark?.let { (symbol, text) ->
            Row(Modifier.offset(x = (at(shown) - 30.dp).coerceIn(0.dp, w - 80.dp)).wrapContentHeight(Alignment.Bottom, unbounded = true).offset(y = (-18).dp)
                .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically) {
                symbol?.let { Icon(it, null, tint = Color.White, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(5.dp)) }
                Text(text, style = digits.copy(color = Color.White))
            }
        }
    }
}

/**
 * The frame at the scrub target, 240 × 135 dp, over the playhead, with the time and chapter under it.
 * Drawn above the bar's own thin box rather than inside it, so it keeps its full height
 * (checkpoint 1: squeezed into the bar's 10 dp it showed as a slim strip).
 */
@Composable
private fun ScrubFrame(item: Item?, server: Server, t: Trickplay?, seconds: Float, x: Dp, width: Dp) {
    val w = 240.dp
    val h = if (t != null && t.width > 0) w * (t.height.toFloat() / t.width) else 0.dp
    Column(Modifier.offset(x = (x - w / 2).coerceIn(0.dp, (width - w).coerceAtLeast(0.dp)))
        .wrapContentHeight(Alignment.Bottom, unbounded = true).offset(y = (-22).dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        if (t != null && item != null && h > 0.dp) {
            val index = ((seconds * 1000) / t.intervalMs.coerceAtLeast(1)).toInt().coerceIn(0, (t.count - 1).coerceAtLeast(0))
            TrickFrame(server, item.id, t, index, Modifier.size(w, h).clip(RoundedCornerShape(10.dp)).background(Color.Black))
            Spacer(Modifier.height(6.dp))
        }
        Text(clock(seconds.toDouble()), style = digits.copy(color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold))
        chapterAt(item, seconds)?.let { Text(it, style = digits.copy(color = Color.White.copy(alpha = 0.75f)), maxLines = 1) }
    }
}

/**
 * One frame cut from a trickplay sheet: the sheet decoded once at its own size in
 * 16-bit colour (about 11 MB for a 10 × 10 sheet of 320 px frames) and only the one
 * cell drawn. Scaling the whole sheet up to the frame's size, as before, asked for
 * about 50 MB on the projector.
 */
@Composable
internal fun TrickFrame(server: Server, id: String, t: Trickplay, index: Int, modifier: Modifier) {
    val perSheet = (t.tiles * t.tiles).coerceAtLeast(1)
    val sheet = index / perSheet
    val cell = index % perSheet
    val context = androidx.compose.ui.platform.LocalContext.current
    val request = androidx.compose.runtime.remember(id, sheet) {
        coil.request.ImageRequest.Builder(context).data(server.trickplaySheet(id, t.width, sheet))
            .size(coil.size.Size.ORIGINAL).bitmapConfig(android.graphics.Bitmap.Config.RGB_565).allowHardware(false).build()
    }
    val painter = coil.compose.rememberAsyncImagePainter(request)
    val bitmap = (painter.state as? coil.compose.AsyncImagePainter.State.Success)?.result?.drawable
        ?.let { (it as? android.graphics.drawable.BitmapDrawable)?.bitmap?.asImageBitmap() }
    androidx.compose.foundation.Canvas(modifier) {
        // The painter must be drawn once for Coil to start the load; nothing shows until the sheet is in.
        with(painter) { draw(androidx.compose.ui.geometry.Size(1f, 1f), alpha = 0f) }
        bitmap ?: return@Canvas
        val cw = bitmap.width / t.tiles; val ch = bitmap.height / t.tiles
        drawImage(bitmap, srcOffset = androidx.compose.ui.unit.IntOffset((cell % t.tiles) * cw, (cell / t.tiles) * ch),
            srcSize = androidx.compose.ui.unit.IntSize(cw, ch), dstSize = androidx.compose.ui.unit.IntSize(size.width.toInt(), size.height.toInt()))
    }
}

/** A round 40 dp button with a 20 dp symbol: frosted at rest, white with a black symbol when chosen. */
@Composable
private fun RoundButton(symbol: ImageVector, label: String, chosen: Boolean) {
    // A dark disc under a light wash, so the button holds on any picture (checkpoint 1).
    Box(Modifier.size(40.dp).background(if (chosen) Color.White else Color(0xFF2A2A2E).copy(alpha = 0.78f), CircleShape),
        contentAlignment = Alignment.Center) {
        Icon(symbol, label, tint = if (chosen) Color.Black else Color.White, modifier = Modifier.size(20.dp))
    }
}

/**
 * Apple's pause screen: the frame dimmed, what this is at the lower left — the
 * title, the episode, two lines of its story — and the time at the upper right.
 */
@Composable
internal fun PauseScreen(item: Item?) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
        // A deeper shade at the lower left, where the words sit, for any picture (checkpoint 2).
        .background(Brush.linearGradient(0f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f),
            start = androidx.compose.ui.geometry.Offset(0f, 0f), end = androidx.compose.ui.geometry.Offset(0f, Float.POSITIVE_INFINITY)))) {
        Box(Modifier.align(Alignment.TopEnd).padding(top = 30.dp, end = 56.dp)) { app.lumiere.android.ui.ClockText() }
        item?.let { cur ->
            Column(Modifier.align(Alignment.BottomStart).padding(start = 56.dp, bottom = 48.dp).fillMaxWidth(0.55f),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (cur.isEpisode) cur.seriesName ?: cur.name else cur.name, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    style = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Color.White))
                if (cur.isEpisode) Text(listOfNotNull(cur.episodeLabel, cur.name).joinToString(" · "), maxLines = 1,
                    style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.8f)))
                cur.overview?.let { Text(it, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    style = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, color = Color.White.copy(alpha = 0.75f))) }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 6.dp)) {
                    Icon(Symbols.play, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Press any button", style = TextStyle(fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f)))
                }
            }
        }
    }
}
