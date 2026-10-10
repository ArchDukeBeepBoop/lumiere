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

    /**
     * The sidebar: a narrow column of glass beside the window's left edge,
     * which on a curve of [DISTANCE_M] sits a little nearer you than its middle.
     */
    const val SIDEBAR_WIDTH_DP = 88
    const val SIDEBAR_HEIGHT_DP = 800
    const val SIDEBAR_WIDTH_M = 0.11f
    val SIDEBAR_HEIGHT_M = SIDEBAR_WIDTH_M * SIDEBAR_HEIGHT_DP / SIDEBAR_WIDTH_DP
    const val SIDEBAR_GAP_M = 0.05f
    /** You face +Z, so your left is +X (right-handed, Y up). If it shows on the right, flip this sign. */
    val SIDEBAR_X_M = WIDTH_M / 2 + SIDEBAR_GAP_M + SIDEBAR_WIDTH_M / 2
    /** How far the window's edge comes toward you: the curve's sagitta at half its width. */
    val EDGE_NEARER_M = DISTANCE_M * (1 - kotlin.math.cos(WIDTH_M / 2 / DISTANCE_M))

    /** How low and high it can be carried. */
    const val MIN_HEIGHT_M = 0.6f
    const val MAX_HEIGHT_M = 2.4f
}
