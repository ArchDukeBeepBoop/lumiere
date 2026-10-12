package app.lumiere.android.spatial

/**
 * The cinema as built (Scripts/env/cinema.py, which writes the same numbers
 * to environments/cinema.json beside its model): one stadium hall round one
 * 20 m screen, twelve rows stepping up from a balcony front, and the five
 * screen sizes as five seats in it — the back row's screen fills 55° of your
 * view, the front row's 115°. The screen is the hall's: a film fills its width
 * (a wide one shorter, as a cinema's masking does) or, narrower than 16:9,
 * its height; it never curves or grows past its frame.
 *
 * In the hall's own frame the screen's face is at z = 0 and the front floor
 * at y = 0; you sit with your feet on your row's floor and your eyes over
 * your seat, so the hall goes round you at [origin]. Pure, so it's tested
 * without a headset.
 */
object CinemaHall {
    const val SCREEN_W = 20f
    const val SCREEN_H = 11.25f
    const val SCREEN_BOTTOM = 1.1f
    const val SCREEN_MIDDLE = SCREEN_BOTTOM + SCREEN_H / 2
    const val ROWS = 12
    const val PITCH = 1.15f
    const val NEAREST = 6.37f
    const val RAKE = 0.38f
    const val FIRST_FLOOR = 1.98f
    /** The row for each size, smallest (the back row) first. */
    val SEAT_ROWS = intArrayOf(11, 7, 4, 2, 0)
    /** A seated viewer's eyes above their row's floor, as the hall was designed for. */
    const val SEAT_EYE = 1.2f
    /** How far the front curtain rises to open, up behind the valance and out of sight. */
    const val CURTAIN_RISE = 14.5f
    /** The balcony front's parapet: its face (z), its top above the front row's floor, and how far back its cap reaches. */
    const val PARAPET_Z = -NEAREST + 0.75f
    const val PARAPET_TOP = 0.78f
    const val PARAPET_DEPTH = 0.18f
    /** A seat back's top above its row's floor, and how far behind its sitter's eyes. */
    const val SEAT_TOP = 1.04f
    const val SEAT_TOP_BEHIND_EYE = 0.33f
    /** The front curtain drawn: across [CURTAIN_HALF_W] either side, from [CURTAIN_BOTTOM] up to [CURTAIN_TOP], its folds' front at [CURTAIN_FRONT]. */
    const val CURTAIN_HALF_W = 11.4f
    const val CURTAIN_BOTTOM = 0.92f
    const val CURTAIN_TOP = 13.7f
    const val CURTAIN_FRONT = -0.71f
    /** The valance's fringe over the screen: its foot, and its face. */
    const val VALANCE_BOTTOM = 12.6f
    const val VALANCE_Z = -1.33f

    fun row(size: Int): Int = SEAT_ROWS[size.coerceIn(0, SEAT_ROWS.lastIndex)]

    /** From the eyes of whoever sits in row [k] (0 the front) to the screen. */
    fun rowDistance(k: Int): Float = NEAREST + PITCH * k

    /** Row [k]'s floor above the hall's front floor. */
    fun rowFloor(k: Int): Float = FIRST_FLOOR + RAKE * k

    /** From your eyes to the screen, in [size]'s row. */
    fun distance(size: Int): Float = rowDistance(row(size))

    /** [size]'s row's floor above the hall's front floor. */
    fun floor(size: Int): Float = rowFloor(row(size))

    /** How far above eyes [eyeY] over your row's floor the screen's middle is. */
    fun aboveEyes(size: Int, eyeY: Float): Float = SCREEN_MIDDLE - floor(size) - eyeY

    /** The picture on the screen for a film [aspect] wide: its width and height. */
    fun picture(aspect: Float): Pair<Float, Float> =
        if (aspect >= SCREEN_W / SCREEN_H) SCREEN_W to SCREEN_W / aspect
        else SCREEN_H * aspect to SCREEN_H

    /**
     * Where the hall's origin is from the floor under your eyes in [size]'s
     * row, in your seat's frame (x left, y up, z ahead): below by your row's
     * height, and ahead by the distance to the screen.
     */
    fun origin(size: Int): FloatArray = floatArrayOf(0f, -floor(size), distance(size))

    /** How far down you look to the screen's foot, metres for each metre ahead, from eyes [eyeY] over [size]'s row. */
    fun footSlope(size: Int, eyeY: Float): Float = (floor(size) + eyeY - SCREEN_BOTTOM) / distance(size)
}
