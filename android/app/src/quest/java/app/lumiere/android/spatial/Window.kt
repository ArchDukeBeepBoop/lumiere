package app.lumiere.android.spatial

/**
 * Lumiere's window in the room, as visionOS places one: a 16:10 pane about
 * 1.4 m away, its middle just below the eyes. Measurements from the spatial
 * app (docs/quest/HANDOVER.md); the Theater's and the handset's panels join
 * these as they are brought over (docs/QUEST_PLAN.md section 0).
 */
object Window {
    /** What the app lays out in: the size of a 1080p TV seen from a sofa. */
    const val WIDTH_DP = 1280
    const val HEIGHT_DP = 800

    const val WIDTH_M = 1.6f
    val HEIGHT_M = WIDTH_M * HEIGHT_DP / WIDTH_DP

    /** 1.4 m is where the Quest's lenses focus, so text there is sharpest and easiest on the eyes. */
    const val DISTANCE_M = 1.4f
    /** Height of its middle above the floor: eye level of someone seated, a little under it standing. */
    const val HEIGHT_ABOVE_FLOOR_M = 1.3f
    /** How far under your eyes its middle comes when it's brought before you in your room. */
    const val BELOW_EYES_M = 0.1f

    /** Away from your room, under the big screen: nearer, and its middle well below your eyes. */
    const val AWAY_DISTANCE_M = 1.3f
    const val AWAY_BELOW_EYES_M = 0.55f

    /** How narrow and wide its corners can make it (its shape kept). */
    const val MIN_WIDTH_M = 0.9f
    const val MAX_WIDTH_M = 3.2f
}
