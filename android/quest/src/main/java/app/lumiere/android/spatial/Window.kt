package app.lumiere.android.spatial

/**
 * Lumiere's window in the room, as visionOS places one: a 16:10 pane a
 * little under two metres away, its middle just below the eyes, curved
 * gently round you so its edges are as sharp as its middle.
 */
object Window {
    /** What the app lays out in: the size of a 1080p TV seen from a sofa, as in the 2D build. */
    const val WIDTH_DP = 1280
    const val HEIGHT_DP = 800

    const val WIDTH_M = 1.6f
    val HEIGHT_M = WIDTH_M * HEIGHT_DP / WIDTH_DP

    /** Its distance, and the radius it curves on — centred on you. */
    const val DISTANCE_M = 1.8f
    /** Height of its middle above the floor: eye level of someone seated, a little under it standing. */
    const val HEIGHT_ABOVE_FLOOR_M = 1.3f

    /** How low and high it can be carried. */
    const val MIN_HEIGHT_M = 0.6f
    const val MAX_HEIGHT_M = 2.4f
}
