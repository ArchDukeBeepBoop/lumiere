package app.lumiere.android.tv.browse

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.ui.Palette
import coil.compose.AsyncImage
import coil.request.ImageRequest

/**
 * The hero (spec §3–§4): the focused Row 0 card's backdrop held top right, its
 * words on the plain ground at the left. Shown only while focus is in Row 0;
 * leaving, it fades and rises 40 dp — alpha and translation only, never size.
 */
@Composable
fun HeroLayer(item: BrowseItem?, visible: Boolean, rowZero: List<BrowseItem>?, focusedIndex: Int) {
    val shown by animateFloatAsState(if (visible) 1f else 0f, tween(300, easing = FastOutSlowInEasing), label = "hero")
    val density = LocalDensity.current
    val context = LocalContext.current
    BoxWithConstraints(Modifier.fillMaxSize().graphicsLayer { alpha = shown; translationY = -(1f - shown) * 40.dp.toPx() }) {
        val artW = with(density) { (maxWidth * 0.85f).roundToPx() }
        val artH = with(density) { (maxHeight * 0.8f).roundToPx() }
        // The neighbours' backdrops fetched ahead (±2), decoded at the size they are shown (§3, §9).
        LaunchedEffect(focusedIndex, rowZero) {
            rowZero ?: return@LaunchedEffect
            for (d in listOf(1, -1, 2, -2)) rowZero.getOrNull(focusedIndex + d)?.backdrop?.let { url ->
                coil.Coil.imageLoader(context).enqueue(ImageRequest.Builder(context).data(url).size(artW, artH).build())
            }
        }
        // Larger than the spec's 70 × 65 %, at the user's request: more picture, the words still on the left's ground.
        Box(Modifier.align(Alignment.TopEnd).fillMaxWidth(0.85f).fillMaxHeight(0.8f)) {
            Crossfade(item, animationSpec = tween(400), label = "backdrop") { it ->
                when {
                    it == null -> Unit
                    it.backdrop != null -> AsyncImage(ImageRequest.Builder(context).data(it.backdrop).size(artW, artH).build(), null,
                        contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    else -> Placeholder(it, Modifier.fillMaxSize(), large = true)
                }
            }
            // Horizontal scrim: the ground colour to clear, over the first 60 % (§3).
            Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to Palette.canvas, 0.22f to Palette.canvas.copy(alpha = 0.6f), 0.5f to Color.Transparent)))
            // Vertical scrim: clear to the ground colour over the bottom 35 % (§3).
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.7f to Color.Transparent, 1f to Palette.canvas)))
        }
        item?.let { h ->
            Column(Modifier.padding(start = BrowseStart, top = maxHeight * 0.14f).widthIn(max = 520.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (h.logo != null) AsyncImage(h.logo, h.title, contentScale = ContentScale.Fit, alignment = Alignment.CenterStart,
                    modifier = Modifier.height(80.dp).widthIn(max = 340.dp))
                else Text(h.title, color = Color.White, fontSize = 38.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                h.meta?.let { Text(it, color = Color.White.copy(alpha = 0.75f), fontSize = 14.sp, maxLines = 1) }
                h.synopsis?.let { Text(it, color = Color.White.copy(alpha = 0.85f), fontSize = 15.sp, lineHeight = 21.sp,
                    maxLines = 2, overflow = TextOverflow.Ellipsis) }
                // The call to action, as a hint rather than a stop: the focused card is what OK plays.
                Text("Play", color = Palette.canvas, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.background(Color.White, RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 7.dp))
            }
        }
    }
}
