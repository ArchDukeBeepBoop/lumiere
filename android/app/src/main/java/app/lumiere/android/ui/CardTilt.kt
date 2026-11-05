package app.lumiere.android.ui

/**
 * A card tipped toward the pointer, as Meta's TV app's posters are on the
 * Quest: where the pointer is on the card, from -1 (left or top) to 1 (right
 * or bottom), and how far that tips it. Pure, so it's tested.
 */
object CardTilt {
    /** The tip at a card's very edge, in degrees. */
    const val DEGREES = 12f

    fun aim(x: Float, y: Float, width: Float, height: Float): androidx.compose.ui.geometry.Offset {
        if (width <= 0f || height <= 0f) return androidx.compose.ui.geometry.Offset.Zero
        return androidx.compose.ui.geometry.Offset((x / width * 2 - 1).coerceIn(-1f, 1f), (y / height * 2 - 1).coerceIn(-1f, 1f))
    }
}
