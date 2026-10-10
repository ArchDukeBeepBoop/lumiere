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

    /**
     * Its distance, and the radius it curves on — centred on you. 1.4 m is
     * where the Quest's lenses focus, so text there is sharpest and easiest
     * on the eyes; at 1.8 m the window read as small and far away.
     */
    const val DISTANCE_M = 1.4f
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
    // You face +Z, so your left is +X (right-handed, Y up); Seats.sidebarBeside places it.

    /** In the cinema the sidebar comes to you: this far away, this far round to your left, a little low. */
    const val NEAR_SIDEBAR_DISTANCE_M = 1.3f
    const val NEAR_SIDEBAR_ANGLE_DEG = 35f
    const val NEAR_SIDEBAR_BELOW_EYES_M = 0.2f

    /** How low and high it can be carried. */
    const val MIN_HEIGHT_M = 0.6f
    const val MAX_HEIGHT_M = 2.4f

    /**
     * The ornament: a strip of glass floating before you, under the screen
     * (Floating: Up Next, the frames as you scrub, the song and its line).
     * The same 800 dp a metre as the window, carried no further than an arm
     * and a half away, and a little below the eyes.
     */
    const val ORNAMENT_WIDTH_DP = 720
    const val ORNAMENT_HEIGHT_DP = 240
    val ORNAMENT_WIDTH_M = WIDTH_M * ORNAMENT_WIDTH_DP / WIDTH_DP
    val ORNAMENT_HEIGHT_M = WIDTH_M * ORNAMENT_HEIGHT_DP / WIDTH_DP
    const val ORNAMENT_DISTANCE_M = 1.1f
    const val ORNAMENT_BELOW_EYES_M = 0.45f

    /** Where a hidden panel waits: far under the floor, where no pointer reaches. */
    fun parked() = com.meta.spatial.core.Pose(com.meta.spatial.core.Vector3(0f, -50f, 0f))
}
