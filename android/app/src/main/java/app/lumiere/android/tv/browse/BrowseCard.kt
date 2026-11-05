package app.lumiere.android.tv.browse

import app.lumiere.android.ui.pointable
import app.lumiere.android.ui.hoverFocuses

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Border
import androidx.tv.material3.Card
import androidx.tv.material3.CardDefaults
import androidx.tv.material3.Glow
import app.lumiere.android.ui.Palette
import coil.compose.AsyncImage

/** Widths per card kind, chosen so a 1.1× focused card is never clipped by the row (spec §7). */
fun cardWidth(type: CardType): Dp = when (type) {
    CardType.Landscape -> 236.dp
    CardType.Portrait -> 136.dp
    CardType.Circle -> 112.dp
}

/**
 * A browse card (spec §7): at rest, art only; focused, 1.1× with a white border
 * and a soft glow, its title and subtitle fading in beneath. Continue Watching
 * keeps its title and a progress bar at all times. The corner radii and the
 * white ring are Apple TV's; the grey ground is the app's.
 */
@Composable
fun BrowseCard(item: BrowseItem, type: CardType, alwaysShowTitle: Boolean, onFocus: () -> Unit, onClick: () -> Unit,
               modifier: Modifier = Modifier) {
    var focused by remember { mutableStateOf(false) }
    val reveal by animateFloatAsState(if (focused || alwaysShowTitle) 1f else 0f, tween(150), label = "title")
    val shape = if (type == CardType.Circle) CircleShape else RoundedCornerShape(12.dp)
    Column(modifier.width(cardWidth(type)), horizontalAlignment = if (type == CardType.Circle) Alignment.CenterHorizontally else Alignment.Start) {
        Card(
            onClick = onClick,
            modifier = Modifier.pointable(onClick = onClick).fillMaxWidth().aspectRatio(when (type) { CardType.Landscape -> 16f / 9f; CardType.Portrait -> 2f / 3f; CardType.Circle -> 1f })
                .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocus() },
            shape = CardDefaults.shape(shape),
            scale = CardDefaults.scale(focusedScale = 1.1f),
            border = CardDefaults.border(focusedBorder = Border(BorderStroke(2.5.dp, Color.White), shape = shape)),
            glow = CardDefaults.glow(focusedGlow = Glow(Color.White.copy(alpha = 0.28f), 14.dp)),
            colors = CardDefaults.colors(containerColor = Palette.surface),
        ) {
            Box(Modifier.fillMaxSize()) {
                if (item.cardArt != null) AsyncImage(item.cardArt, item.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                else Placeholder(item, Modifier.fillMaxSize())
                item.progress?.let { p ->
                    Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(10.dp).height(4.dp)
                        .background(Color.White.copy(alpha = 0.3f), RoundedCornerShape(2.dp))) {
                        Box(Modifier.fillMaxWidth(p).height(4.dp).background(Color.White, RoundedCornerShape(2.dp)))
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Column(Modifier.graphicsLayer { alpha = reveal }) {
            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, color = Palette.textPrimary,
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold))
            item.subtitle?.let { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis, color = Palette.textSecondary,
                style = MaterialTheme.typography.labelMedium) }
        }
    }
}

/** Local art for the sample catalog: the item's own colour and its initials, no network. */
@Composable
fun Placeholder(item: BrowseItem, modifier: Modifier, large: Boolean = false) {
    val top = Color.hsv(item.hue, 0.45f, 0.55f)
    val bottom = Color.hsv((item.hue + 40f) % 360f, 0.55f, 0.25f)
    Box(modifier.background(Brush.linearGradient(listOf(top, bottom))), contentAlignment = Alignment.Center) {
        Text(item.title.split(' ').mapNotNull { it.firstOrNull()?.toString() }.take(2).joinToString(""),
            color = Color.White.copy(alpha = 0.55f), fontSize = if (large) 120.sp else 26.sp, fontWeight = FontWeight.Bold)
    }
}
