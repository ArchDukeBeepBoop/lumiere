package app.lumiere.android.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.api.Item
import app.lumiere.android.api.TICKS_PER_SECOND
import coil.compose.AsyncImage
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.aspectRatio

/** The compact strip (docs/TV_UX_PLAN.md §1.3) — the information area: the chosen card's picture right, its name, facts and story left. */
@Composable
fun InfoArea(item: Item, server: app.lumiere.android.api.Server, modifier: Modifier) {
    // On the Quest the strip is words alone: the chosen card is itself the picture, lifted
    // under the pointer, so a second copy of it here was only clutter.
    if (app.lumiere.android.Flavor.quest) Box(modifier.background(Palette.canvas.copy(alpha = 0.9f))) {
        InfoText(item)
    } else Box(modifier.background(Palette.canvas)) {
        Box(Modifier.align(Alignment.TopEnd).fillMaxWidth(0.6f).fillMaxHeight()) {
            Crossfade(item, animationSpec = tween(app.lumiere.android.Motion.ms(400)), label = "info") { it ->
                imageFor(it, server, CardShape.Wide, 1280)?.let { art -> AsyncImage(art, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
            }
            Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to Palette.canvas, 0.3f to Palette.canvas.copy(alpha = 0.55f), 0.6f to Color.Transparent)))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Palette.canvas)))
        }
        InfoText(item)
    }
}

/** The chosen card's name, facts and story, low on the left. */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.InfoText(item: Item) {
    Column(Modifier.align(Alignment.BottomStart).padding(start = 56.dp, bottom = 10.dp).widthIn(max = 460.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(if (item.isEpisode) item.seriesName ?: item.name else item.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = TvType.strip)
        Text(listOfNotNull(item.episodeLabel, item.year?.toString(), item.officialRating,
            item.runtimeTicks?.let { val m = it / TICKS_PER_SECOND / 60; if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m" },
            item.genres.firstOrNull()).joinToString(" · "), style = TvType.meta, maxLines = 1)
        item.overview?.let { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TvType.body) }
    }
}
