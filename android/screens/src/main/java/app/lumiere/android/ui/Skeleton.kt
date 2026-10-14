package app.lumiere.android.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/*
 * Loading placeholders in the shapes of what is coming: posters, wide
 * stills, a title's name and story, its buttons. Each is drawn at the size
 * the real layout gives it and in the cards' own grey, so when the real
 * thing arrives it simply fills in and nothing on the page moves.
 */

/** The cards' corners (Cards.kt), so a placeholder becomes its card without a jump. */
internal val SkeletonCard = RoundedCornerShape(10.dp)

/**
 * The soft light every placeholder on a screen shares, passing across them
 * together from left to right and resting a moment between passes. One
 * infinite transition drives a whole screen, not one per card, which a 2 GB
 * TV would feel; its position is read only while drawing, so the sweep
 * redraws the placeholders and never recomposes them. With motion reduced
 * there is no light, only the still grey.
 */
@Stable
class Sheen internal constructor(private val progress: State<Float>?, private val across: Float) {
    /** Half the light's width, in pixels: a sixth of the screen. */
    internal val band get() = across / 6f

    /** The light's centre across a placeholder whose left edge is [left] pixels in; null while it rests or stands still. */
    internal fun centre(left: Float): Float? {
        val p = progress?.value ?: return null
        if (p > CROSSING) return null
        return -band + (across + band * 2) * (p / CROSSING) - left
    }
}

/** The share of each two-second pass the light spends crossing; for the rest it rests. */
private const val CROSSING = 0.7f

/** One [Sheen] for a screen's placeholders; call it once, where the screen's loading state is known. */
@Composable
fun rememberSheen(): Sheen {
    val across = with(LocalDensity.current) { LocalConfiguration.current.screenWidthDp.dp.toPx() }
    if (app.lumiere.android.Motion.reduced) return remember(across) { Sheen(null, across) }
    val pass = rememberInfiniteTransition(label = "sheen")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(2_000, easing = LinearEasing)), label = "pass")
    return remember(pass, across) { Sheen(pass, across) }
}

/**
 * Draws this as a placeholder: the cards' grey in [shape], the [sheen]'s
 * light passing over it where the light is at that moment on the screen.
 */
@Composable
fun Modifier.skeleton(sheen: Sheen, shape: Shape = SkeletonCard): Modifier {
    // Where it sits on the screen, kept outside state: the light is placed while drawing.
    val left = remember { floatArrayOf(0f) }
    return this
        .onGloballyPositioned { left[0] = it.positionInRoot().x }
        .clip(shape)
        .drawWithCache {
            val band = sheen.band
            val ground = Palette.surface
            val light = Brush.linearGradient(listOf(Color.Transparent, Palette.textPrimary.copy(alpha = 0.07f), Color.Transparent),
                start = Offset(-band, 0f), end = Offset(band, band * 0.3f))
            onDrawBehind {
                drawRect(ground)
                val x = sheen.centre(left[0]) ?: return@onDrawBehind
                if (x + band < 0f || x - band > size.width) return@onDrawBehind
                translate(x, 0f) { drawRect(light, topLeft = Offset(-x, 0f), size = size) }
            }
        }
}

/**
 * A line of [style]'s text still to come: a bar as tall as its letters,
 * centred in the height the line will take. Its width comes from [modifier].
 */
@Composable
fun SkeletonText(sheen: Sheen, style: TextStyle, modifier: Modifier) {
    val size = if (style.fontSize.isSp) style.fontSize else 14.sp
    val line = with(LocalDensity.current) { (if (style.lineHeight.isSp) style.lineHeight else size * 1.18f).toDp() }
    val letters = with(LocalDensity.current) { (size * 0.72f).toDp() }
    Box(modifier.height(line), contentAlignment = Alignment.CenterStart) {
        Box(Modifier.fillMaxWidth().height(letters).skeleton(sheen, RoundedCornerShape(4.dp)))
    }
}

/** A poster to come in a grid's cell, its name and year beneath, as ItemCard draws it with `fill`. */
@Composable
fun SkeletonGridPoster(sheen: Sheen) {
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).skeleton(sheen))
        Spacer(Modifier.height(6.dp))
        SkeletonText(sheen, MaterialTheme.typography.titleMedium, Modifier.fillMaxWidth(0.8f))
        SkeletonText(sheen, MaterialTheme.typography.labelMedium, Modifier.fillMaxWidth(0.3f))
    }
}

/** A button to come on a TV: the pill's height, taller on a Quest where every target is. */
@Composable
private fun SkeletonPill(sheen: Sheen, width: Dp) =
    Box(Modifier.width(width).height(if (app.lumiere.android.AppBuild.quest) 52.dp else 40.dp).skeleton(sheen, CircleShape))

/**
 * TV Home's first load, before anything has been saved: the spotlight's
 * title, facts, story and buttons low on the left in [hero]'s height, then
 * Up Next as wide cards, the libraries, and new titles as posters, at the
 * row widths Home measures from the screen. [gutter] and [gap] are Home's own.
 */
@Composable
fun TvHomeSkeleton(hero: Dp, gutter: Dp, gap: Dp, wide: Dp, library: Dp, poster: Dp) {
    val sheen = rememberSheen()
    // As tall as its rows need, the screen's edge cutting the last, so no card is squeezed to fit.
    Column(Modifier.fillMaxSize().background(Palette.canvas).clipToBounds().wrapContentHeight(Alignment.Top, unbounded = true)) {
        Box(Modifier.fillMaxWidth().height(hero)) {
            Column(Modifier.align(Alignment.BottomStart).padding(start = gutter, bottom = 28.dp).widthIn(max = 640.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.height(120.dp), contentAlignment = Alignment.BottomStart) {
                    Box(Modifier.width(360.dp).height(64.dp).skeleton(sheen, RoundedCornerShape(8.dp)))
                }
                SkeletonText(sheen, TextStyle(fontSize = 15.sp), Modifier.width(300.dp))
                Column {
                    listOf(1f, 1f, 0.6f).forEach { SkeletonText(sheen, TextStyle(fontSize = 16.sp, lineHeight = 23.sp), Modifier.fillMaxWidth(it)) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { SkeletonPill(sheen, 128.dp); SkeletonPill(sheen, 128.dp) }
            }
        }
        SkeletonShelfRow(sheen, gutter, gap, 110.dp) {
            Column(Modifier.width(wide)) {
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).skeleton(sheen))
                Spacer(Modifier.height(10.dp))
                SkeletonText(sheen, TextStyle(fontSize = 15.sp), Modifier.fillMaxWidth(0.7f))
                SkeletonText(sheen, MaterialTheme.typography.labelMedium, Modifier.fillMaxWidth(0.45f))
            }
        }
        SkeletonShelfRow(sheen, gutter, gap, 100.dp) { Box(Modifier.width(library).aspectRatio(16f / 9f).skeleton(sheen)) }
        SkeletonShelfRow(sheen, gutter, gap, 220.dp) { Box(Modifier.width(poster).aspectRatio(2f / 3f).skeleton(sheen)) }
    }
}

/** A Home row as TvShelf lays it out, below the spotlight's 8 dp: its title, then its cards on past the screen's edge. */
@Composable
private fun SkeletonShelfRow(sheen: Sheen, gutter: Dp, gap: Dp, title: Dp, card: @Composable () -> Unit) {
    Column(Modifier.padding(top = 8.dp + 18.dp)) {
        SkeletonText(sheen, TextStyle(fontSize = 19.sp), Modifier.padding(start = gutter).width(title))
        LazyRow(contentPadding = PaddingValues(horizontal = gutter, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(gap),
            userScrollEnabled = false) { items(6) { card() } }
    }
}

/**
 * A title's page on the TV while it loads (TvDetail): its name, facts, story,
 * Play and the round buttons low on the left where the page will put them,
 * and the row of pills beneath. Held back a moment and faded in, so a title
 * that comes straight from the cache never flashes grey bars first.
 */
@Composable
fun TvDetailSkeleton() {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(150); shown = true }
    val fade by animateFloatAsState(if (shown) 1f else 0f, tween(app.lumiere.android.Motion.ms(250)), label = "skeleton")
    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.canvas)) {
        if (!shown) return@BoxWithConstraints
        val sheen = rememberSheen()
        val h = maxHeight
        Column(Modifier.graphicsLayer { alpha = fade }) {
            Box(Modifier.fillMaxWidth().height(h * 0.86f)) {
                Column(Modifier.align(Alignment.BottomStart).padding(start = 56.dp, bottom = 24.dp).widthIn(max = 680.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.height(120.dp), contentAlignment = Alignment.BottomStart) {
                        Box(Modifier.width(380.dp).height(64.dp).skeleton(sheen, RoundedCornerShape(8.dp)))
                    }
                    SkeletonText(sheen, TextStyle(fontSize = 15.sp), Modifier.width(320.dp))
                    Column {
                        listOf(1f, 1f, 1f, 0.55f).forEach { SkeletonText(sheen, TextStyle(fontSize = 16.sp, lineHeight = 23.sp), Modifier.fillMaxWidth(it)) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SkeletonPill(sheen, 190.dp)
                        // The round buttons, each named beneath (Watched, Favourite, More).
                        repeat(3) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Box(Modifier.size(52.dp).skeleton(sheen, CircleShape))
                                SkeletonText(sheen, MaterialTheme.typography.labelMedium, Modifier.width(44.dp))
                            }
                        }
                    }
                }
            }
            // Seasons for a show, Cast & Crew and More Like This for a film: pills either way.
            Row(Modifier.padding(start = 56.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf(96.dp, 110.dp, 96.dp).forEach { SkeletonPill(sheen, it) }
            }
        }
    }
}
