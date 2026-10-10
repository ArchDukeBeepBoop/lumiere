package app.lumiere.android.spatial

/**
 * The screen's sizes, as numbers. In your room: five steps of the window's
 * own size, from a laptop's to a big TV's seen across a sofa. In the cinema:
 * one screen, eight metres wide, seen from the back row, the middle or the
 * front, the way Apple TV's Cinema seats you; how wide it looks follows.
 */
object Seats {
    /** The window's scale at each room size; 1 is 1.6 m wide. */
    val ROOM = floatArrayOf(0.75f, 1f, 1.3f, 1.7f, 2.2f)

    /** The cinema screen's scale: 1.6 m × 5 = 8 m wide. */
    const val CINEMA_SCALE = 5f
    /** How far each row sits from the screen: back, middle, front. */
    val ROW_DISTANCE = floatArrayOf(11.5f, 8.5f, 6f)
    /** How far above your eyes the screen's middle sits, as in a theatre. */
    const val ABOVE_EYES = 0.7f

    fun roomScale(size: Int) = ROOM[size.coerceIn(0, ROOM.lastIndex)]
    fun rowDistance(seat: Int) = ROW_DISTANCE[seat.coerceIn(0, ROW_DISTANCE.lastIndex)]

    /** How wide [widthM] at [distanceM] looks, in degrees. */
    fun angleDegrees(widthM: Float, distanceM: Float): Float =
        Math.toDegrees(2 * kotlin.math.atan((widthM / 2 / distanceM).toDouble())).toFloat()
}
