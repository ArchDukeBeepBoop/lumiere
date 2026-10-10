package app.lumiere.android.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.OpenApp
import app.lumiere.android.api.Item
import coil.compose.AsyncImage

/**
 * The cinema's screen while you browse: the title you're on, its backdrop
 * across the whole screen and its name in the corner, as Apple TV fills the
 * top of its Home and Bigscreen its screen before the film. Home sets it as
 * a selection settles, a title's page while it's open; the Quest shows it on
 * the big screen in the cinema, the dark and space.
 */
object Marquee {
    /** Set on the Quest; elsewhere nothing reads [item]. */
    var enabled = false
    var item by mutableStateOf<Item?>(null)

    /** Set [shown] as the selection, if the marquee is in use. */
    fun show(shown: Item?) { if (enabled && shown != null) item = shown }

    @Composable
    fun Panel() = WithAppImages {
        val server = OpenApp.state?.server
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (server == null) return@Box
            Crossfade(item, animationSpec = tween(900), label = "marquee") { shown ->
                if (shown == null) return@Crossfade
                Box(Modifier.fillMaxSize()) {
                    imageFor(shown, server, CardShape.Wide, 1920)?.let {
                        AsyncImage(it, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                    // A shade from the top-left corner for the title: there it stays clear of the
                    // window, which stands before the screen's lower middle.
                    Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(
                        0f to Color.Black.copy(alpha = 0.7f), 0.55f to Color.Transparent)))
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                        0f to Color.Black.copy(alpha = 0.5f), 0.4f to Color.Transparent, 0.8f to Color.Transparent,
                        1f to Color.Black.copy(alpha = 0.6f))))
                    Column(Modifier.align(Alignment.TopStart).padding(start = 96.dp, top = 80.dp).fillMaxWidth(0.4f)) {
                        val logo = shown.logoTag?.let { server.imageUrl(shown.id, "Logo", it, 900) }
                        if (logo != null) AsyncImage(logo, shown.name, contentScale = ContentScale.Fit, alignment = Alignment.TopStart,
                            modifier = Modifier.width(620.dp).height(200.dp))
                        else Text(if (shown.isEpisode) shown.seriesName ?: shown.name else shown.name,
                            fontSize = 72.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        val facts = listOfNotNull(
                            shown.episodeLabel?.takeIf { shown.isEpisode },
                            shown.year?.toString(),
                            shown.runtimeTicks?.let { "${it / 600_000_000} min" },
                            shown.officialRating,
                        ).joinToString("  ·  ")
                        if (facts.isNotEmpty()) Text(facts, fontSize = 28.sp, color = Color.White.copy(alpha = 0.8f),
                            modifier = Modifier.padding(top = 16.dp))
                        shown.overview?.let {
                            Text(it, style = MaterialTheme.typography.bodyLarge.copy(fontSize = 26.sp, lineHeight = 36.sp),
                                color = Color.White.copy(alpha = 0.75f), maxLines = 2, overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(top = 12.dp))
                        }
                    }
                }
            }
        }
    }
}
