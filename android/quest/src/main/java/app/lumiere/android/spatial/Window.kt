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


    /** How narrow and wide its corners can make it (its shape kept). */
    const val MIN_WIDTH_M = 0.9f
    const val MAX_WIDTH_M = 3.2f

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

    /**
     * The poster wall: a band of glass curved round you, 2.2 m away and
     * about 155 degrees wide, 1.6 m tall, its middle a little above your eyes. Laid out
     * at 400 dp a metre (twice the window's size per dp) so a poster is
     * about a third of a metre wide, and drawn at 240 dpi.
     */
    const val WALL_WIDTH_DP = 2400
    const val WALL_HEIGHT_DP = 640
    const val WALL_DP_PER_M = 400f
    const val WALL_RADIUS_M = 2.2f
    const val WALL_DPI = 240
    /** Raised so the middle row is a touch above your eyes and the lowest isn't at your knees. */
    const val WALL_ABOVE_EYES_M = 0.25f

    /**
     * The Theater's transport: a bar of glass near your hands, below the
     * screen's line of sight, tilted to face your eyes; the panel is clear
     * above the bar, where audio and subtitles open. 1100 × 560 dp laid out,
     * 0.82 m across; the bar is its lowest 250 dp.
     */
    const val TRANSPORT_WIDTH_DP = 1100
    const val TRANSPORT_HEIGHT_DP = 560
    /** The bar's own height within the panel, to keep it where it was as the panel grew above it. */
    const val TRANSPORT_BAR_DP = 250
    const val TRANSPORT_WIDTH_M = 0.82f
    val TRANSPORT_HEIGHT_M = TRANSPORT_WIDTH_M * TRANSPORT_HEIGHT_DP / TRANSPORT_WIDTH_DP
    const val TRANSPORT_DISTANCE_M = 0.95f
    const val TRANSPORT_BELOW_EYES_M = 0.42f
    /** Over the transport, while the Theater is up, the ornament (Up Next, the scrub frames). */
    const val ORNAMENT_OVER_TRANSPORT_BELOW_EYES_M = 0.12f
    /** "More": the window comes this far before you, over the Theater, for its tracks and info. */
    const val ASKED_WINDOW_DISTANCE_M = 1.25f
}
