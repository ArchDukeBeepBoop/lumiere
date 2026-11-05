package app.lumiere.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The TV's one type scale, Apple TV-sized for a ten-foot screen (docs/TV_UX_PLAN.md §0).
 * Every TV page takes its sizes from here rather than choosing its own.
 */
object TvType {
    val display = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.Bold, lineHeight = 44.sp, color = Color.White)
    val title = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
    val strip = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
    val row = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.92f))
    val body = TextStyle(fontSize = 13.5.sp, lineHeight = 19.sp, color = Color.White.copy(alpha = 0.85f))
    val meta = TextStyle(fontSize = 12.5.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.7f))
    val badge = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.8f))
    val caption = TextStyle(fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f))
    val button = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.Black)
}

/** The TV's one spacing grid (docs/TV_UX_PLAN.md §0). */
object TvSpace {
    val margin = 56.dp
    val cardGap = 24.dp
    val rowGap = 20.dp
    val section = 32.dp
    /** A round button: larger in the headset, where a hand aims (Horizon OS asks 48 dp at the least). */
    val button get() = if (app.lumiere.android.Flavor.quest) 56.dp else 40.dp
    /**
     * The banner's share of the screen, and the compact strip's, and where a chosen row lands.
     * Taller in a headset, whose curved window opens on the picture, as Apple's TV app does.
     */
    val banner get() = if (app.lumiere.android.Flavor.quest) 0.70f else 0.62f
    /** Room at a page's foot (the Quest's tab bar is at the top now, so none). */
    val foot get() = 0.dp
    const val strip = 0.24f
    const val landing = 0.26f
}
