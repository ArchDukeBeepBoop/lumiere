package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min

/**
 * The cinema round the screen, as a list of boxes: a stadium-seated hall
 * where you sit high in a raked row, so a screen many metres across stands
 * with its middle near your eye line, as from the best seats. Rows of seats
 * step down toward a stage, side walls carry acoustic panels, black masking
 * frames the screen, small amber lights mark the aisle steps, and a row
 * rises behind you. About a hundred boxes, flat-shaded: a few draw calls'
 * worth on a Quest.
 *
 * Laid out in your seat's own frame: you at the origin on the real floor
 * (y = 0, your row's platform), facing +Z, your left +X; the screen's
 * middle at (0, [screenMiddleY], [distance]). Pure, so it's tested without a
 * headset; Theatre turns it into entities.
 */
object Auditorium {
    enum class Kind { FLOOR, STEP, SEAT, SEAT_BACK, WALL, PANEL, CEILING, STAGE, MASK, SCREEN_WALL, AISLE_LIGHT, EXIT_SIGN, BALCONY }

    /** One box: its middle and its size, in metres. */
    data class Part(val kind: Kind, val x: Float, val y: Float, val z: Float, val w: Float, val h: Float, val d: Float) {
        val top get() = y + h / 2
        val bottom get() = y - h / 2
        val front get() = z + d / 2
        val back get() = z - d / 2
    }

    const val ROW_PITCH = 1.1f
    /** How much each row steps down: from a gentle hall's to a steep stadium's. */
    const val MIN_RAKE = 0.25f
    const val MAX_RAKE = 0.6f
    private const val PARAPET = 0.3f

    /** The rake that brings [rows] rows down to the stage under a screen whose foot is at [screenBottom]. */
    fun rakeFor(screenBottom: Float, rows: Int): Float =
        (-(screenBottom - 0.9f) / (rows + 1)).coerceIn(MIN_RAKE, MAX_RAKE)
    /** Your own seat: kept clear this far either side of you, so nothing stands where you are. */
    const val CLEAR_BESIDE_YOU = 0.75f
    private const val SEAT_HEIGHT = 0.45f
    private const val BACK_HEIGHT = 0.5f
    private const val SEAT_DEPTH = 0.55f
    private const val BEHIND = 2.6f

    /**
     * The hall for a screen [screenWidth] × [screenHeight] whose middle is at
     * height [screenMiddleY], [distance] ahead, seen from eyes at [eyeY].
     */
    fun build(screenWidth: Float, screenHeight: Float, screenMiddleY: Float, distance: Float, eyeY: Float = 1.2f): List<Part> {
        val parts = mutableListOf<Part>()
        val hallWidth = max(screenWidth + 6f, 16f)
        val half = hallWidth / 2
        val screenBottom = screenMiddleY - screenHeight / 2
        val screenTop = screenMiddleY + screenHeight / 2
        // Rows ahead step down until four metres short of the screen: each row at least as steep as
        // your sightline to the screen's foot, so no seat back ever crosses it, and steeper still if the
        // floor must reach the stage. Where even the steepest rake can't keep under that line (a near
        // seat before a huge screen), there are no rows ahead: you're at a balcony's front.
        val sightSlope = (eyeY - screenBottom) / distance
        val byDistance = max(0, ((distance - 4f) / ROW_PITCH).toInt())
        val rows = if (sightSlope * ROW_PITCH * 1.1f > MAX_RAKE) 0 else byDistance
        val rake = max(rakeFor(screenBottom, rows), sightSlope * ROW_PITCH * 1.1f).coerceIn(MIN_RAKE, MAX_RAKE)
        val lastRowFloor = -rows * rake
        val frontFloor = min(lastRowFloor - rake, screenBottom - 0.9f)
        /** The height of your sightline to the screen's foot, [z] ahead. */
        fun sight(z: Float) = eyeY - sightSlope * z
        val ceiling = max(screenTop + 2.5f, 4.5f)
        val seatHalf = half - 1.4f          // aisles down both sides

        // Your row: its platform, and seats either side of you.
        parts += Part(Kind.FLOOR, 0f, -0.05f, -0.3f, hallWidth, 0.1f, 1.8f)
        seatBlock(parts, CLEAR_BESIDE_YOU, seatHalf, 0f, 0f)
        seatBlock(parts, -seatHalf, -CLEAR_BESIDE_YOU, 0f, 0f)
        // A row behind you, a step up, and the back wall.
        parts += Part(Kind.STEP, 0f, rake / 2, -1.1f - 0.3f, hallWidth, rake, 1.2f)
        seatBlock(parts, -seatHalf, seatHalf, rake, -1.1f)
        parts += Part(Kind.WALL, 0f, (ceiling + 0f) / 2, -BEHIND, hallWidth, ceiling + 0.2f, 0.2f)

        // The rows ahead, each a step lower: a riser, then its seats; an amber light at each aisle step.
        for (k in 1..rows) {
            val z = k * ROW_PITCH
            val floor = -k * rake
            parts += Part(Kind.STEP, 0f, floor - 0.05f, z, hallWidth, 0.1f, ROW_PITCH)
            parts += Part(Kind.STEP, 0f, floor + rake / 2, z - ROW_PITCH / 2, hallWidth, rake, 0.04f)
            seatBlock(parts, -seatHalf, seatHalf, floor, z)
            parts += Part(Kind.AISLE_LIGHT, half - 0.7f, floor + 0.03f, z - ROW_PITCH / 2 + 0.06f, 0.18f, 0.04f, 0.04f)
            parts += Part(Kind.AISLE_LIGHT, -half + 0.7f, floor + 0.03f, z - ROW_PITCH / 2 + 0.06f, 0.18f, 0.04f, 0.04f)
        }
        // Where the rows end high above the front floor, a balcony front: a low parapet, so it never hides the screen's foot.
        val balconyZ = rows * ROW_PITCH + ROW_PITCH / 2
        if (lastRowFloor - frontFloor > 1.2f) {
            val top = min(lastRowFloor + PARAPET, sight(balconyZ) - 0.15f)
            parts += Part(Kind.BALCONY, 0f, (top + frontFloor) / 2, balconyZ + 0.1f, hallWidth, top - frontFloor, 0.2f)
        }
        // The front floor and the stage under the screen.
        val frontStart = if (rows > 0) balconyZ else 0.6f
        parts += Part(Kind.FLOOR, 0f, frontFloor - 0.05f, (frontStart + distance + 1f) / 2, hallWidth, 0.1f, distance + 1f - frontStart)
        val stageTop = screenBottom - 0.15f
        parts += Part(Kind.STAGE, 0f, (frontFloor + stageTop) / 2, distance - 0.9f, screenWidth + 2f, stageTop - frontFloor, 1.8f)

        // Walls from the floor to the ceiling, with acoustic panels every 2.5 m; the ceiling over all.
        val hallLength = distance + 1f + BEHIND
        val hallMiddleZ = (distance + 1f - BEHIND) / 2
        val wallHeight = ceiling - frontFloor
        val wallMiddleY = (ceiling + frontFloor) / 2
        parts += Part(Kind.WALL, half + 0.1f, wallMiddleY, hallMiddleZ, 0.2f, wallHeight, hallLength)
        parts += Part(Kind.WALL, -half - 0.1f, wallMiddleY, hallMiddleZ, 0.2f, wallHeight, hallLength)
        var z = -BEHIND + 1.5f
        while (z < distance - 1f) {
            parts += Part(Kind.PANEL, half - 0.04f, wallMiddleY + 0.5f, z, 0.08f, wallHeight * 0.6f, 1.2f)
            parts += Part(Kind.PANEL, -half + 0.04f, wallMiddleY + 0.5f, z, 0.08f, wallHeight * 0.6f, 1.2f)
            z += 2.5f
        }
        parts += Part(Kind.CEILING, 0f, ceiling + 0.1f, hallMiddleZ, hallWidth + 0.4f, 0.2f, hallLength)

        // Behind the screen a dark wall; round it, black masking — above, and either side.
        parts += Part(Kind.SCREEN_WALL, 0f, wallMiddleY, distance + 0.6f, hallWidth, wallHeight, 0.2f)
        val maskZ = distance + 0.08f
        parts += Part(Kind.MASK, 0f, (screenTop + ceiling) / 2 + 0.05f, maskZ, hallWidth, ceiling - screenTop + 0.1f, 0.05f)
        val sideWidth = half - screenWidth / 2
        if (sideWidth > 0.05f) {
            parts += Part(Kind.MASK, screenWidth / 2 + sideWidth / 2, wallMiddleY, maskZ, sideWidth, wallHeight, 0.05f)
            parts += Part(Kind.MASK, -screenWidth / 2 - sideWidth / 2, wallMiddleY, maskZ, sideWidth, wallHeight, 0.05f)
        }
        // Green exit signs high in the front corners.
        parts += Part(Kind.EXIT_SIGN, half - 0.8f, screenTop + 0.8f, distance - 0.5f, 0.6f, 0.25f, 0.05f)
        parts += Part(Kind.EXIT_SIGN, -half + 0.8f, screenTop + 0.8f, distance - 0.5f, 0.6f, 0.25f, 0.05f)
        return parts
    }

    /** A bench of seats from [fromX] to [toX], on a floor at [floor], its row at [z]: a seat, and a back behind it. */
    private fun seatBlock(parts: MutableList<Part>, fromX: Float, toX: Float, floor: Float, z: Float) {
        val w = toX - fromX
        if (w <= 0.2f) return
        val x = (fromX + toX) / 2
        parts += Part(Kind.SEAT, x, floor + SEAT_HEIGHT / 2, z + 0.05f, w, SEAT_HEIGHT, SEAT_DEPTH)
        parts += Part(Kind.SEAT_BACK, x, floor + SEAT_HEIGHT + BACK_HEIGHT / 2 - 0.1f, z - SEAT_DEPTH / 2 + 0.05f, w, BACK_HEIGHT + 0.2f, 0.12f)
    }

    /** Each kind's colour under full house lights, linear 0..1. */
    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.FLOOR -> Triple(0.10f, 0.09f, 0.12f)
        Kind.STEP -> Triple(0.12f, 0.11f, 0.14f)
        Kind.SEAT -> Triple(0.45f, 0.07f, 0.09f)
        Kind.SEAT_BACK -> Triple(0.40f, 0.06f, 0.08f)
        Kind.WALL -> Triple(0.17f, 0.14f, 0.13f)
        Kind.PANEL -> Triple(0.26f, 0.21f, 0.17f)
        Kind.CEILING -> Triple(0.06f, 0.06f, 0.07f)
        Kind.STAGE -> Triple(0.14f, 0.11f, 0.10f)
        Kind.MASK -> Triple(0.012f, 0.012f, 0.014f)
        Kind.SCREEN_WALL -> Triple(0.02f, 0.02f, 0.025f)
        Kind.BALCONY -> Triple(0.20f, 0.16f, 0.14f)
        Kind.AISLE_LIGHT -> Triple(1.0f, 0.62f, 0.22f)
        Kind.EXIT_SIGN -> Triple(0.2f, 0.95f, 0.45f)
    }

    /** How much of the film's light a kind catches (what faces the screen most catches most); lights shine on their own. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.AISLE_LIGHT, Kind.EXIT_SIGN, Kind.MASK -> 0f
        Kind.SEAT, Kind.STAGE, Kind.BALCONY -> 0.55f
        Kind.CEILING -> 0.25f
        else -> 0.4f
    }

    /**
     * A part's colour with the house lights at [level] (1 up, about 0.12
     * during a film) and the film's [tint] spilling as they go down. The
     * hall stays visible in the dark; the lights never dim.
     */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> {
        val (r, g, b) = baseColour(kind)
        if (kind == Kind.AISLE_LIGHT || kind == Kind.EXIT_SIGN) return Triple(r, g, b)
        val house = 0.3f + 0.7f * level
        val (tr, tg, tb) = tint ?: Triple(0.5f, 0.5f, 0.55f)
        val s = spill(kind) * (1f - level) * 0.35f
        fun mix(base: Float, t: Float) = (base * house + t * s).coerceIn(0f, 1f)
        return Triple(mix(r, tr), mix(g, tg), mix(b, tb))
    }
}
