package app.lumiere.android.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.lumiere.android.api.Item
import coil.compose.AsyncImage
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * The Quest window's ground, behind every page: colour rather than pictures, as
 * Horizon OS's own panels are — the app's midnight, lit by a broad glow at the
 * top left and a deeper one low on the right. The glow takes on the colour of
 * Home's spotlight title (QuestGround.tint), easing from one to the next, and
 * keeps it on the pages after; the app's periwinkle until there is one.
 */
@Composable
fun Modifier.questGround(): Modifier {
    val glow by androidx.compose.animation.animateColorAsState(QuestGround.section ?: QuestGround.tint ?: Palette.accent,
        tween(app.lumiere.android.Motion.ms(900)), label = "glow")
    val canvas = Palette.canvas
    return drawBehind {
        drawRect(canvas)
        drawRect(Brush.radialGradient(listOf(glow.copy(alpha = 0.5f), Color.Transparent), center = Offset(0f, 0f), radius = size.maxDimension * 0.9f))
        drawRect(Brush.radialGradient(listOf(glow.copy(red = glow.red * 0.8f, green = glow.green * 0.45f).copy(alpha = 0.4f), Color.Transparent),
            center = Offset(size.width, size.height), radius = size.maxDimension))
    }
}

/** The colour the Quest's ground leans to: Home's spotlight title's, from its artwork. */
object QuestGround {
    var tint by mutableStateOf<Color?>(null)
    /** A section's own colour while its page is open (the rail sets it): Movies warm, TV Shows cool. */
    var section by mutableStateOf<Color?>(null)

    /** The colour of each section of the rail; null where the page's title colours it instead. */
    fun sectionColour(label: String?): Color? = when (label) {
        "Movies" -> Color(1f, 0.62f, 0.30f)
        "TV Shows" -> Color(0.35f, 0.62f, 1f)
        "Immersive" -> Color(0.40f, 0.95f, 0.85f)
        "Music" -> Color(1f, 0.40f, 0.62f)
        "Watchlist" -> Color(1f, 0.84f, 0.35f)
        else -> null
    }

    /** A title's colour as a glow: at full strength, so a dark poster still colours rather than greys. */
    fun glowOf(c: ArtColour.Rgb): Color {
        val peak = maxOf(c.r, c.g, c.b).coerceAtLeast(1e-3f)
        return Color(c.r / peak, c.g / peak, c.b / peak)
    }
}

/** The spotlight's picture as a framed card, on the Quest's colour ground: lit and tipped where you point. */
@Composable
internal fun HeroArt(item: Item, server: app.lumiere.android.api.Server, modifier: Modifier) {
    var aim by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val x by androidx.compose.animation.core.animateFloatAsState(aim.x, androidx.compose.animation.core.spring(stiffness = 200f), label = "heroX")
    val y by androidx.compose.animation.core.animateFloatAsState(aim.y, androidx.compose.animation.core.spring(stiffness = 200f), label = "heroY")
    val density = androidx.compose.ui.platform.LocalDensity.current
    Crossfade(item, modifier.aspectRatio(16f / 9f), animationSpec = tween(app.lumiere.android.Motion.ms(500)), label = "heroArt") { shown ->
        Box(Modifier.fillMaxSize()
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val e = awaitPointerEvent()
                        val p = e.changes.firstOrNull()?.position ?: continue
                        aim = if (e.type == androidx.compose.ui.input.pointer.PointerEventType.Exit) androidx.compose.ui.geometry.Offset.Zero
                            else CardTilt.aim(p.x, p.y, size.width.toFloat(), size.height.toFloat())
                    }
                }
            }
            .graphicsLayer {
                rotationY = x * CardTilt.DEGREES * 0.8f; rotationX = -y * CardTilt.DEGREES * 0.8f
                cameraDistance = 14f * density.density
                shadowElevation = with(density) { 28.dp.toPx() }
                shape = RoundedCornerShape(22.dp); clip = true
            }
            .background(Palette.surface)) {
            // A window onto the scene rather than a print: the picture sits deeper than its frame,
            // so it slides the other way as the frame tips, as the posters in Meta's TV app do.
            AsyncImage(imageFor(shown, server, CardShape.Wide, 1200), shown.name, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().graphicsLayer {
                    scaleX = 1.12f; scaleY = 1.12f
                    translationX = -x * size.width * 0.05f; translationY = -y * size.height * 0.05f
                })
            // The light where you point, and a bright rim along the edge that faces it.
            Box(Modifier.fillMaxSize().drawBehind {
                drawRect(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.22f), Color.Transparent),
                    center = Offset((x + 1) / 2 * size.width, (y + 1) / 2 * size.height), radius = size.maxDimension * 0.6f))
                drawRect(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.18f * (kotlin.math.abs(x) + kotlin.math.abs(y)).coerceAtMost(1f)), Color.Transparent),
                    start = Offset((x + 1) / 2 * size.width, (y + 1) / 2 * size.height), end = Offset(size.width / 2, size.height / 2)))
            })
        }
    }
}
