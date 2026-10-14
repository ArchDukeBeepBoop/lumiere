package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A round glass button for the Quest's own panels (tab bar, transport):
 * brighter where you point, filled when [chosen]. It hears a pinch or a
 * trigger as a tap — Compose for TV's buttons don't, outside the window.
 */
@Composable
fun GlassButton(icon: ImageVector, label: String, chosen: Boolean = false, caption: String? = null,
                size: Dp = 48.dp, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when {
        chosen -> Palette.textPrimary
        hovered -> Color.White.copy(alpha = 0.22f)
        else -> Color.Transparent
    }
    val ink = if (chosen) Palette.canvas else Palette.textPrimary
    Box(Modifier.size(size).background(ground, CircleShape).hoverable(source)
        .clickable(interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = ink, modifier = Modifier.size(size / 2).then(if (caption != null) Modifier.padding(bottom = 10.dp) else Modifier))
        if (caption != null) androidx.compose.material3.Text(caption, color = ink,
            style = androidx.compose.ui.text.TextStyle(fontSize = 11.sp), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 6.dp))
    }
}

/**
 * The glass of the Quest's own floating panels: nearly opaque, untinted,
 * with a fine light edge. The window's overlays are translucent over their
 * film, but a panel standing in front of a bright screen let the screen show
 * through it, and it read as a reflection.
 */
fun Modifier.spatialGlass(radius: Int = 24): Modifier = this
    .background(Palette.surface.copy(alpha = 0.95f), androidx.compose.foundation.shape.RoundedCornerShape(radius.dp))
    .border(1.dp, Color.White.copy(alpha = 0.10f), androidx.compose.foundation.shape.RoundedCornerShape(radius.dp))
