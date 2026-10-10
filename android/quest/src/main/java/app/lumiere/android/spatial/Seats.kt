package app.lumiere.android.spatial

import kotlin.math.cos
import kotlin.math.sin

/**
 * The screen's sizes and shapes, as numbers. In your room: five steps of
 * the window's own size, from a laptop's to a big TV's seen across a sofa.
 * In the cinema: one screen seen from the back row, the middle or the
 * front, the way Apple TV's Cinema seats you; how wide it looks follows.
 *
 * A size is the panel's real size in metres, never a Scale: on the headset
 * a scaled panel looked no bigger while the pointer aimed as if it were,
 * so buttons went dead and the cinema couldn't be worked (Cinema.resize).
 */
object Seats {
    /** A screen: its width and height, and the radius it curves on (very large: flat). */
    data class Shape(val widthM: Float, val heightM: Float, val radiusM: Float)

    /** Each room size as a multiple of the window's own 1.6 m; the middle one is where everyone starts. */
    val ROOM = floatArrayOf(0.6f, 0.8f, 1f, 1.25f, 1.55f)

    /**
     * The cinema screen: 4.8 m wide (3 m tall), with the rows placed for the
     * angles of Apple TV's Cinema. Smaller and nearer than a real cinema's
     * eight metres at the same angle, so it stands on its stage near your
     * eye line instead of towering over you.
     */
    const val CINEMA_WIDTH_M = 4.8f
    /** How far each row sits from the screen: back, middle, front. */
    val ROW_DISTANCE = floatArrayOf(6.9f, 5.1f, 3.6f)
    /** The screen's middle sits this far above your eyes, as in a theatre, when its height allows. */
    const val ABOVE_EYES = 0.15f
    /** The stage under the screen, whose top the screen's foot never goes below. */
    const val STAGE_M = 0.3f

    /** "Flat": a curve so gentle it bulges a few centimetres over the widest screen. */
    const val FLAT_RADIUS_M = 60f

    fun roomScale(size: Int) = ROOM[size.coerceIn(0, ROOM.lastIndex)]
    fun rowDistance(seat: Int) = ROW_DISTANCE[seat.coerceIn(0, ROW_DISTANCE.lastIndex)]

    /** The room's screen at [size]: curved, it is centred on you at the window's distance. */
    fun room(size: Int, curved: Boolean): Shape {
        val w = Window.WIDTH_M * roomScale(size)
        return Shape(w, w * Window.HEIGHT_DP / Window.WIDTH_DP, if (curved) Window.DISTANCE_M else FLAT_RADIUS_M)
    }

    /** The cinema's screen from [seat]: curved, centred on that row. */
    fun cinema(seat: Int, curved: Boolean): Shape =
        Shape(CINEMA_WIDTH_M, CINEMA_WIDTH_M * Window.HEIGHT_DP / Window.WIDTH_DP, if (curved) rowDistance(seat) else FLAT_RADIUS_M)

    /**
     * Height of the screen's middle for eyes at [eyeY] (from the floor): a
     * little above them, but never so low that a screen [heightM] tall sinks
     * into the stage or floor.
     */
    fun screenMiddleY(eyeY: Float, heightM: Float): Float = maxOf(eyeY + ABOVE_EYES, STAGE_M + heightM / 2)

    /**
     * Where the sidebar sits beside a screen of [shape], in the screen's own
     * space (its middle at the origin, you towards -Z, its left at +X):
     * carried on along the curve just past the left edge, and turned to face
     * you. Returns x, z, and the direction from you to it (x, z), which is
     * the way it faces away from you.
     */
    fun sidebarBeside(shape: Shape): FloatArray {
        val along = shape.widthM / 2 + Window.SIDEBAR_GAP_M + Window.SIDEBAR_WIDTH_M / 2
        val r = shape.radiusM
        val a = along / r
        return floatArrayOf(r * sin(a), r * cos(a) - r, sin(a), cos(a))
    }

    /** How wide [widthM] at [distanceM] looks, in degrees. */
    fun angleDegrees(widthM: Float, distanceM: Float): Float =
        Math.toDegrees(2 * kotlin.math.atan((widthM / 2 / distanceM).toDouble())).toFloat()
}
