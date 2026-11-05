package app.lumiere.android.spatial

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Choosing where a film plays, as Apple TV and NEX offer their
 * environments: a card for each place showing the place itself — the view
 * ahead from its seat, cut from its own 360° picture — rather than a list of
 * names. Opened from the player's More menu; it floats before you over the
 * Theater and goes when you've chosen.
 */
object PlacePicker {
    /** Open now (TheaterStage shows the panel before you while it is). */
    var open by mutableStateOf(false)
    /** What a choice does: set by the stage. */
    var onPick: (Place) -> Unit = {}
    var current: () -> Place = { Place.ROOM }
    /** The panel's width in the room. */
    const val WIDTH_M = 1.2f

    @Composable
    fun Panel() {
        val chosen = current()
        Column(Modifier.fillMaxSize().background(Color(0xF013162A), RoundedCornerShape(28.dp)).padding(28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text("Where to Watch", style = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Color(0xFFF3F4FA)))
            LazyVerticalGrid(GridCells.Fixed(3), horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp), contentPadding = PaddingValues(bottom = 8.dp)) {
                items(Place.entries) { p -> Card(p, p == chosen) { onPick(p); open = false } }
            }
        }
    }

    @Composable
    private fun Card(place: Place, chosen: Boolean, onClick: () -> Unit) {
        val context = LocalContext.current
        // The middle of the place's picture, ahead from its seat, decoded small (an eighth): a postcard, not 32 MB.
        val thumb = remember(place) {
            place.picture?.let { id ->
                runCatching {
                    val full = BitmapFactory.decodeResource(context.resources, id, BitmapFactory.Options().apply { inSampleSize = 8 })
                    val w = full.width / 3; val h = (w * 9 / 16).coerceAtMost(full.height)
                    android.graphics.Bitmap.createBitmap(full, (full.width - w) / 2, (full.height - h) / 2, w, h).asImageBitmap()
                }.getOrNull()
            }
        }
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(16.dp))
            .background(if (place == Place.ROOM) Color(0xFF2D3150) else Color.Black)
            .border(if (chosen) 3.dp else 0.dp, if (chosen) Color(0xFF9296FF) else Color.Transparent, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick), contentAlignment = Alignment.BottomStart) {
            thumb?.let { Image(it, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f)))))
            Text(place.label, modifier = Modifier.padding(12.dp),
                style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White))
        }
    }
}
