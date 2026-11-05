package app.lumiere.android.spatial

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import app.lumiere.android.player.Theater
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth

/**
 * The film's captions under its screen: white with a soft shadow, centred,
 * the latest lines at the bottom, nothing at all between lines — the panel
 * is clear, so the room shows through it.
 */
@Composable
fun TheaterCaptions() {
    val lines = Theater.cues.mapNotNull { it.text?.toString()?.trim()?.takeIf { t -> t.isNotEmpty() } }
    // Picture subtitles (a Blu-ray's PGS, a DVD's VobSub) have no text, only a bitmap: shown as they are.
    val pictures = Theater.cues.mapNotNull { it.bitmap }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Bottom) {
            pictures.forEach { b ->
                androidx.compose.foundation.Image(b.asImageBitmap(), null,
                    Modifier.fillMaxWidth(0.8f).aspectRatio(b.width.toFloat() / b.height.coerceAtLeast(1)))
            }
            // The player's own Size and Look (Subtitles › Style), as the window's captions take them.
            val prefs = app.lumiere.android.OpenApp.state?.settings
            val size = listOf(24f, 30f, 36f, 42f)[(prefs?.subtitleSize ?: 1).coerceIn(0, 3)]
            val look = prefs?.subtitleStyle ?: 0
            lines.forEach { line ->
                Text(line, textAlign = TextAlign.Center, color = Color(0xFFF3F4FA),
                    modifier = if (look == 2) Modifier.background(Color.Black.copy(alpha = 0.66f)).padding(horizontal = 10.dp, vertical = 2.dp) else Modifier,
                    style = TextStyle(fontSize = size.sp, lineHeight = (size * 1.2f).sp, fontWeight = FontWeight.Medium,
                        shadow = when (look) { 0 -> Shadow(Color.Black, blurRadius = 8f); 1 -> Shadow(Color.Black, androidx.compose.ui.geometry.Offset(3f, 3f), 6f); else -> null }))
            }
        }
    }
}
