package app.lumiere.android.spatial

import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * The cabin round the screen, as a list of boxes: a modern timber great
 * room with the film on its end wall. A warm oak floor; the screen 5 cm in
 * front of a dark timber wall, slim fins either side of it and a low walnut
 * credenza under it; side walls of floor-to-ceiling glass between timber
 * piers, thin dark mullions across it, the lake at dusk (the sky) beyond; a
 * high ceiling on exposed beams; a stone fireplace with its fire on your
 * left, a lamp on your right, a low cognac sofa behind and either side of
 * you on a wool rug, and the back wall three metres behind you, lined with
 * books; and the things of someone who lives there (see lived). Textured
 * timber, stone and cloth, unlit: at most [MOST_BOXES] boxes.
 *
 * The screen is a wall 5.5 m across with its middle just above your eyes,
 * so seated, a 16:9 film's foot comes below your own floor, and even a
 * 2.39:1 one's leaves no room for the credenza. Then the great room is a
 * step down before you: you sit on a raised oak dais, and the floor under
 * the screen is low enough for the credenza beneath its foot. The dais's
 * edge and every step stay under your sightline to the screen's foot.
 *
 * Laid out in your seat's own frame as Auditorium is: you at the origin on
 * the real floor (y = 0), facing +Z, your left +X; the screen's middle at
 * (0, [screenMiddleY], [distance]). Pure, so it's tested without a headset;
 * a Scenery turns it into entities.
 */
object Cabin {
    enum class Kind {
        FLOOR, STEP, RUG, SOFA, LAMP_STAND, LAMP, WALL, BACK_WALL, FRONT_WALL, FIN, MULLION,
        CEILING, BEAM, CREDENZA, CHIMNEY, HEARTH, MANTEL, FIRE,
        // What makes it lived in: shelves of books, tables with a mug and a candle on them, cushions
        // and a throw, plants, pictures, logs and the flames on them, speakers, pendant lights.
        SHELF, BOOKS, BOOK, TABLE, MUG, CANDLE, FLAME, CUSHION, THROW, POT, STEM, LEAF,
        FRAME, ART_ABSTRACT, ART_LANDSCAPE, LOG, EMBER, SPEAKER, GRILLE, PENDANT_CORD, PENDANT, VASE,
    }

    /**
     * The most boxes the room may be: each is a draw call, and with the
     * screen, the window and the sky the Quest 3S keeps its frame rate well
     * inside this.
     */
    const val MOST_BOXES = 150

    /** The back wall stands this far behind you. */
    const val BEHIND = 3f
    /** A great room's ceiling, higher only for a screen that would reach it. */
    const val CEILING = 5f
    /** How far in front of its wall the screen stands. */
    const val SCREEN_GAP = 0.05f
    /** Your own place, kept clear this far either side of you, as the cinema keeps your seat. */
    const val CLEAR_BESIDE_YOU = 0.6f
    /** The sofa's back, low enough to stay under your eyes when you sit. */
    const val SOFA_BACK_TOP = 0.78f
    private const val WALL = 0.2f
    private const val CREDENZA_HEIGHT = 0.42f
    private const val CREDENZA_DEPTH = 0.45f
    /** Under the screen's foot: the credenza and a hand's width over it. */
    private const val UNDER_SCREEN = CREDENZA_HEIGHT + 0.08f
    private const val STEP_RISE = 0.2f
    private const val SOFA_HALF = 1.5f
    private const val SOFA_SEAT = 0.42f
    /** Solid timber at each end of a side wall, and between its glass bays. */
    private const val CORNER = 0.5f
    private const val PIER = 0.45f
    private const val BAY = 1.6f
    /** The glazing's cross bar, at a door's height. */
    private const val TRANSOM = 2.7f
    /** The fireplace's wall runs from the back to here. */
    private const val FIRE_WALL_END = -0.6f
    private const val BEAM_PITCH = 1.6f

    /**
     * The room for a screen [screenWidth] × [screenHeight] whose middle is at
     * height [screenMiddleY], [distance] ahead, seen from eyes at [eyeY], with
     * your sightline to its foot coming down [footSlope] metres for each
     * metre ahead (TheaterGeometry.footSlope: steeper for a curved screen,
     * whose ends come nearer).
     */
    fun build(
        screenWidth: Float, screenHeight: Float, screenMiddleY: Float, distance: Float, eyeY: Float = 1.2f,
        footSlope: Float = (eyeY - (screenMiddleY - screenHeight / 2)) / distance,
    ): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
        val half = max(screenWidth / 2 + 1.5f, 4.25f)
        val screenBottom = screenMiddleY - screenHeight / 2
        val screenTop = screenMiddleY + screenHeight / 2
        val ceiling = max(CEILING, screenTop + 0.6f)
        val wallFace = distance + SCREEN_GAP
        val front = wallFace + WALL
        val rear = -BEHIND - WALL
        val credenzaFront = wallFace - CREDENZA_DEPTH

        // The floor: your own level throughout, or a dais you sit on and the great room a step down,
        // its edge well before your sightline to the screen's foot reaches your floor.
        val low = min(0f, screenBottom - UNDER_SCREEN)
        val base = low - 0.1f
        val edge = if (low == 0f) front else min(0.7f, 0.7f * eyeY / footSlope.coerceAtLeast(1e-3f))
        if (edge >= front) parts += Block.between(Kind.FLOOR, -half, half, base, 0f, rear, front)
        else {
            val steps = ceil(-low / STEP_RISE).toInt().coerceIn(1, 4)
            val rise = -low / steps
            val tread = min(0.3f, (credenzaFront - 0.1f - edge) / steps)
            parts += Block.between(Kind.FLOOR, -half, half, base, 0f, rear, edge)
            for (k in 1 until steps)
                parts += Block.between(Kind.STEP, -half, half, base, -k * rise, edge + (k - 1) * tread, edge + k * tread)
            parts += Block.between(Kind.FLOOR, -half, half, base, low, edge + (steps - 1) * tread, front)
        }

        // A wool rug on your level, and the low sofa on it: its back behind you, its seats either
        // side of your own place (you have your own seat, as in the cinema), its arms at the ends.
        val onYourLevel = min(edge, credenzaFront) - 0.1f
        parts += Block.between(Kind.RUG, -1.4f, 1.4f, 0f, 0.015f, -1.7f, min(1.0f, onYourLevel - 0.2f))
        val seatFront = min(0.3f, onYourLevel)
        parts += Block.between(Kind.SOFA, -SOFA_HALF - 0.18f, SOFA_HALF + 0.18f, 0f, SOFA_BACK_TOP, -0.8f, -0.55f)
        for (side in floatArrayOf(1f, -1f)) {
            parts += Block.between(Kind.SOFA, min(side * CLEAR_BESIDE_YOU, side * SOFA_HALF), max(side * CLEAR_BESIDE_YOU, side * SOFA_HALF),
                0f, SOFA_SEAT, -0.55f, seatFront)
            parts += Block.between(Kind.SOFA, min(side * SOFA_HALF, side * (SOFA_HALF + 0.18f)), max(side * SOFA_HALF, side * (SOFA_HALF + 0.18f)),
                0f, 0.6f, -0.55f, seatFront)
        }
        // A floor lamp at the sofa's right end, its shade a soft glow.
        parts += Block.between(Kind.LAMP_STAND, -2.13f, -2.07f, 0f, 1.35f, -0.38f, -0.32f)
        parts += Block.between(Kind.LAMP, -2.28f, -1.92f, 1.35f, 1.7f, -0.53f, -0.17f)

        // The back wall, the front wall the screen stands before, and the ceiling over all.
        parts += Block.between(Kind.BACK_WALL, -half - WALL, half + WALL, base, ceiling, rear, -BEHIND)
        parts += Block.between(Kind.FRONT_WALL, -half - WALL, half + WALL, base, ceiling, wallFace, front)
        parts += Block.between(Kind.CEILING, -half - WALL, half + WALL, ceiling, ceiling + 0.2f, rear, front)
        // Slim timber fins either side of the screen, standing off the wall.
        val finFrom = screenWidth / 2 + 0.4f
        val finTo = half - 0.3f
        if (finTo - finFrom > 0.3f) for (i in 0 until 4) {
            val x = finFrom + (finTo - finFrom) * i / 3
            for (side in floatArrayOf(1f, -1f))
                parts += Block.between(Kind.FIN, min(side * (x - 0.03f), side * (x + 0.03f)), max(side * (x - 0.03f), side * (x + 0.03f)),
                    low, ceiling, wallFace - 0.08f, wallFace)
        }
        // Exposed beams across the ceiling.
        var z = -BEHIND + 0.8f
        while (z < wallFace - 0.4f) {
            parts += Block.between(Kind.BEAM, -half, half, ceiling - 0.3f, ceiling, z - 0.11f, z + 0.11f)
            z += BEAM_PITCH
        }
        // The credenza under the screen, against the wall.
        val credenzaHalf = min(screenWidth * 0.36f, 2.2f)
        parts += Block.between(Kind.CREDENZA, -credenzaHalf, credenzaHalf, low, low + CREDENZA_HEIGHT, credenzaFront, wallFace)

        // The side walls: glass between timber piers, the left one solid round the fireplace.
        sideWall(parts, half, half + WALL, rear, FIRE_WALL_END, front, base, ceiling)
        sideWall(parts, -half - WALL, -half, rear, rear + CORNER, front, base, ceiling)
        // The fireplace: a stone chimney breast against the left wall, its fire, hearth and mantel.
        parts += Block.between(Kind.CHIMNEY, half - 0.45f, half, 0f, ceiling, -2.5f, -1.1f)
        parts += Block.between(Kind.FIRE, half - 0.47f, half - 0.44f, 0.3f, 0.85f, -2.1f, -1.5f)
        parts += Block.between(Kind.HEARTH, half - 0.85f, half - 0.45f, 0f, 0.1f, -2.4f, -1.2f)
        parts += Block.between(Kind.MANTEL, half - 0.6f, half - 0.45f, 1.15f, 1.22f, -2.55f, -1.05f)

        lived(parts, half, ceiling, low, wallFace, screenWidth, edge, credenzaFront, eyeY, footSlope)
        return parts
    }

    /**
     * What makes the room someone's: a wall of books behind you, a table at
     * each end of the sofa (a mug, a candle, a book left open), cushions and
     * a throw, a tall plant in the corner, pictures over the shelves and the
     * mantel, logs in the fire and a stack beside it, candles on the mantel,
     * a speaker either side of the screen, pendant lights over the sofa, and
     * a coffee table before you where the sightline to the screen leaves
     * room for one.
     */
    private fun lived(
        parts: MutableList<Block<Kind>>, half: Float, ceiling: Float, low: Float, wallFace: Float, screenWidth: Float,
        edge: Float, credenzaFront: Float, eyeY: Float, footSlope: Float,
    ) {
        // The bookcase across the back wall: three bays of five shelves, a few with something else on them.
        val back = -BEHIND
        val caseHalf = min(2.6f, half - 1.2f)
        val bayWidth = 2 * caseHalf / 3
        for (i in 0..3) {
            val x = -caseHalf + i * bayWidth
            parts += Block.between(Kind.SHELF, x - 0.02f, x + 0.02f, 0f, 2.4f, back, back + 0.36f)
        }
        val levels = floatArrayOf(0f, 0.46f, 0.92f, 1.38f, 1.84f, 2.3f)
        for (y in levels) parts += Block.between(Kind.SHELF, -caseHalf, caseHalf, y, y + 0.03f, back, back + 0.36f)
        for (bay in 0 until 3) for (row in 0 until 5) {
            val x0 = -caseHalf + bay * bayWidth + 0.04f
            val x1 = x0 + bayWidth - 0.08f
            val y0 = levels[row] + 0.03f
            when (bay to row) {
                1 to 2 -> {   // a celadon vase
                    val m = (x0 + x1) / 2
                    parts += Block.between(Kind.VASE, m - 0.09f, m + 0.09f, y0, y0 + 0.32f, back + 0.08f, back + 0.26f)
                }
                0 to 3 -> {   // a framed photograph, leaning
                    parts += Block.between(Kind.FRAME, x0 + 0.1f, x0 + 0.5f, y0, y0 + 0.34f, back + 0.04f, back + 0.06f)
                    parts += Block.between(Kind.ART_LANDSCAPE, x0 + 0.13f, x0 + 0.47f, y0 + 0.03f, y0 + 0.31f, back + 0.06f, back + 0.07f)
                    parts += Block.between(Kind.BOOKS, x0 + 0.62f, x1, y0, y0 + 0.3f, back + 0.06f, back + 0.3f)
                }
                2 to 1 -> {   // a little plant
                    val m = (x0 + x1) / 2
                    parts += Block.between(Kind.POT, m - 0.1f, m + 0.1f, y0, y0 + 0.16f, back + 0.08f, back + 0.28f)
                    parts += Block.between(Kind.LEAF, m - 0.18f, m + 0.18f, y0 + 0.16f, y0 + 0.36f, back + 0.04f, back + 0.32f)
                }
                else -> parts += Block.between(Kind.BOOKS, x0, x1, y0, y0 + 0.28f + 0.02f * ((bay + row) % 3), back + 0.06f, back + 0.3f)
            }
        }
        // A picture over the bookcase.
        parts += Block.between(Kind.FRAME, -0.95f, 0.95f, 2.75f, 3.95f, back, back + 0.04f)
        parts += Block.between(Kind.ART_ABSTRACT, -0.85f, 0.85f, 2.85f, 3.85f, back + 0.04f, back + 0.05f)

        // A table at each end of the sofa: on your left a candle and a book, on your right a mug and two books.
        val outside = SOFA_HALF + 0.22f
        for (side in floatArrayOf(1f, -1f)) {
            val x0 = min(side * outside, side * (outside + 0.45f)); val x1 = max(side * outside, side * (outside + 0.45f))
            val z0 = if (side > 0) -0.5f else -0.2f
            parts += Block.between(Kind.TABLE, x0, x1, 0.47f, 0.5f, z0, z0 + 0.45f)
            parts += Block.between(Kind.TABLE, (x0 + x1) / 2 - 0.05f, (x0 + x1) / 2 + 0.05f, 0f, 0.47f, z0 + 0.17f, z0 + 0.27f)
            val mx = (x0 + x1) / 2
            if (side > 0) {
                parts += Block.between(Kind.CANDLE, mx + 0.05f, mx + 0.12f, 0.5f, 0.64f, z0 + 0.1f, z0 + 0.17f)
                parts += Block.between(Kind.FLAME, mx + 0.075f, mx + 0.095f, 0.64f, 0.69f, z0 + 0.125f, z0 + 0.145f)
                parts += Block.between(Kind.BOOK, mx - 0.16f, mx + 0.02f, 0.5f, 0.53f, z0 + 0.2f, z0 + 0.4f)
            } else {
                parts += Block.between(Kind.MUG, mx + 0.06f, mx + 0.14f, 0.5f, 0.6f, z0 + 0.08f, z0 + 0.16f)
                parts += Block.between(Kind.BOOK, mx - 0.17f, mx + 0.02f, 0.5f, 0.54f, z0 + 0.18f, z0 + 0.42f)
                parts += Block.between(Kind.BOOK, mx - 0.15f, mx + 0.0f, 0.54f, 0.57f, z0 + 0.2f, z0 + 0.38f)
            }
        }
        // Cushions against the sofa's back, and a knitted throw over its left end.
        parts += Block.between(Kind.CUSHION, 1.02f, 1.44f, SOFA_SEAT, SOFA_SEAT + 0.36f, -0.55f, -0.42f)
        parts += Block.between(Kind.CUSHION, -1.44f, -1.02f, SOFA_SEAT, SOFA_SEAT + 0.36f, -0.55f, -0.42f)
        parts += Block.between(Kind.CUSHION, -0.98f, -0.64f, SOFA_SEAT, SOFA_SEAT + 0.3f, -0.55f, -0.44f)
        parts += Block.between(Kind.THROW, 0.7f, 1.3f, SOFA_BACK_TOP, SOFA_BACK_TOP + 0.03f, -0.82f, -0.53f)
        parts += Block.between(Kind.THROW, 0.7f, 1.3f, SOFA_SEAT + 0.05f, SOFA_BACK_TOP, -0.55f, -0.52f)

        // A tall plant in the back corner on your right: a pot, a stem, leaves at different heights.
        val px = -half + 0.55f; val pz = back + 0.5f
        parts += Block.between(Kind.POT, px - 0.22f, px + 0.22f, 0f, 0.45f, pz - 0.22f, pz + 0.22f)
        parts += Block.between(Kind.STEM, px - 0.025f, px + 0.025f, 0.45f, 1.75f, pz - 0.025f, pz + 0.025f)
        for ((dx, y, dz, r) in listOf(
            floatArrayOf(0.12f, 1.0f, 0.05f, 0.34f), floatArrayOf(-0.15f, 1.25f, -0.08f, 0.38f), floatArrayOf(0.08f, 1.5f, -0.12f, 0.36f),
            floatArrayOf(-0.05f, 1.75f, 0.1f, 0.4f), floatArrayOf(0.18f, 1.95f, 0.02f, 0.3f), floatArrayOf(-0.16f, 2.05f, -0.04f, 0.26f),
        )) parts += Block.between(Kind.LEAF, px + dx - r / 2, px + dx + r / 2, y - r * 0.35f, y + r * 0.35f, pz + dz - r / 2, pz + dz + r / 2)

        // The fire: two logs on the hearth, flames on them, embers glowing under; a stack of logs beside it.
        val fx = half - 0.62f
        parts += Block.between(Kind.LOG, fx - 0.08f, fx + 0.08f, 0.1f, 0.22f, -2.05f, -1.55f)
        parts += Block.between(Kind.LOG, fx - 0.06f, fx + 0.1f, 0.18f, 0.3f, -1.95f, -1.6f)
        parts += Block.between(Kind.EMBER, fx - 0.1f, fx + 0.1f, 0.1f, 0.13f, -2.0f, -1.6f)
        for ((i, z) in floatArrayOf(-1.95f, -1.8f, -1.66f).withIndex()) {
            val h = 0.26f + 0.08f * ((i + 1) % 2)
            parts += Block.between(Kind.FLAME, fx - 0.04f, fx + 0.04f, 0.28f, 0.28f + h, z - 0.05f, z + 0.05f)
        }
        for (row in 0 until 3) for (k in 0 until 3 - row) {
            val y = 0.08f + row * 0.15f
            val x = half - 0.42f + k * 0.13f - row * 0.065f - 0.13f
            if (row + k < 5) parts += Block.between(Kind.LOG, x - 0.065f, x + 0.065f, y - 0.07f, y + 0.07f, -0.98f, -0.58f)
        }
        // Two candles on the mantel, and a picture over it.
        for (z in floatArrayOf(-2.4f, -1.25f)) {
            parts += Block.between(Kind.CANDLE, half - 0.56f, half - 0.49f, 1.22f, 1.42f, z - 0.035f, z + 0.035f)
            parts += Block.between(Kind.FLAME, half - 0.535f, half - 0.515f, 1.42f, 1.47f, z - 0.01f, z + 0.01f)
        }
        parts += Block.between(Kind.FRAME, half - 0.48f, half - 0.45f, 1.5f, 2.4f, -2.3f, -1.3f)
        parts += Block.between(Kind.ART_LANDSCAPE, half - 0.49f, half - 0.48f, 1.56f, 2.34f, -2.24f, -1.36f)

        // A tall speaker either side of the screen, beyond its edges, its grille facing you.
        val sx = screenWidth / 2 + 0.3f
        for (side in floatArrayOf(1f, -1f)) {
            val x0 = min(side * sx, side * (sx + 0.32f)); val x1 = max(side * sx, side * (sx + 0.32f))
            parts += Block.between(Kind.SPEAKER, x0, x1, low, low + 1.1f, wallFace - 0.62f, wallFace - 0.26f)
            parts += Block.between(Kind.GRILLE, x0 + 0.03f, x1 - 0.03f, low + 0.1f, low + 1.02f, wallFace - 0.64f, wallFace - 0.62f)
        }
        // Pendant lights hanging over the sofa, behind you and to either side.
        for (x in floatArrayOf(1.25f, -1.25f)) {
            parts += Block.between(Kind.PENDANT_CORD, x - 0.008f, x + 0.008f, 2.5f, ceiling, -1.21f, -1.19f)
            parts += Block.between(Kind.PENDANT, x - 0.16f, x + 0.16f, 2.24f, 2.5f, -1.36f, -1.04f)
        }
        // A coffee table before you, where it fits on your level and under your sightline to the screen's foot.
        val tableTop = 0.42f
        val reach = if (footSlope > 1e-3f) (eyeY - tableTop - 0.08f) / footSlope else Float.MAX_VALUE
        val far = minOf(edge - 0.12f, credenzaFront - 0.3f, reach, 1.25f)
        if (far - 0.55f >= 0.45f) {
            parts += Block.between(Kind.TABLE, -0.5f, 0.5f, tableTop - 0.04f, tableTop, 0.55f, far)
            parts += Block.between(Kind.TABLE, -0.4f, 0.4f, 0f, tableTop - 0.04f, 0.62f, far - 0.07f)
            parts += Block.between(Kind.BOOK, -0.35f, -0.08f, tableTop, tableTop + 0.04f, 0.62f, 0.82f)
            parts += Block.between(Kind.MUG, 0.18f, 0.26f, tableTop, tableTop + 0.1f, 0.65f, 0.73f)
        }
    }

    /**
     * A side wall between [x0] and [x1] across, from [from] to [to] along
     * the room: solid timber to [solidTo] and for a corner's width at the far
     * end; between them glass bays parted by piers, each bay with a mullion up
     * its middle and a transom across it.
     */
    private fun sideWall(parts: MutableList<Block<Kind>>, x0: Float, x1: Float, from: Float, solidTo: Float, to: Float, base: Float, ceiling: Float) {
        parts += Block.between(Kind.WALL, x0, x1, base, ceiling, from, solidTo)
        parts += Block.between(Kind.WALL, x0, x1, base, ceiling, to - CORNER, to)
        val span = to - CORNER - solidTo
        if (span <= 0f) return
        val bays = max(1, ((span + PIER) / (BAY + PIER)).toInt())
        val bay = (span - (bays - 1) * PIER) / bays
        val mid = (x0 + x1) / 2
        for (i in 0 until bays) {
            val z0 = solidTo + i * (bay + PIER)
            if (i > 0) parts += Block.between(Kind.WALL, x0, x1, base, ceiling, z0 - PIER, z0)
            parts += Block.between(Kind.MULLION, mid - 0.03f, mid + 0.03f, base, ceiling, z0 + bay / 2 - 0.03f, z0 + bay / 2 + 0.03f)
            parts += Block.between(Kind.MULLION, mid - 0.03f, mid + 0.03f, TRANSOM - 0.03f, TRANSOM + 0.03f, z0, z0 + bay)
        }
    }

    /** Each kind's colour with the lights up, linear 0..1: oak, cedar, smoked timber, cognac, stone, fire. */
    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.FLOOR -> Triple(0.32f, 0.19f, 0.09f)
        Kind.STEP -> Triple(0.28f, 0.165f, 0.08f)
        Kind.RUG -> Triple(0.26f, 0.23f, 0.19f)
        Kind.SOFA -> Triple(0.26f, 0.10f, 0.04f)
        Kind.LAMP_STAND -> Triple(0.03f, 0.03f, 0.03f)
        Kind.LAMP -> Triple(1.0f, 0.75f, 0.45f)
        Kind.WALL -> Triple(0.30f, 0.20f, 0.12f)
        Kind.BACK_WALL -> Triple(0.27f, 0.18f, 0.11f)
        Kind.FRONT_WALL -> Triple(0.035f, 0.025f, 0.02f)
        Kind.FIN -> Triple(0.06f, 0.04f, 0.03f)
        Kind.MULLION -> Triple(0.025f, 0.025f, 0.028f)
        Kind.CEILING -> Triple(0.22f, 0.14f, 0.08f)
        Kind.BEAM -> Triple(0.09f, 0.055f, 0.03f)
        Kind.CREDENZA -> Triple(0.08f, 0.045f, 0.025f)
        Kind.CHIMNEY -> Triple(0.11f, 0.105f, 0.10f)
        Kind.HEARTH -> Triple(0.07f, 0.068f, 0.065f)
        Kind.MANTEL -> Triple(0.20f, 0.12f, 0.06f)
        Kind.FIRE -> Triple(1.0f, 0.42f, 0.10f)
        Kind.SHELF -> Triple(0.10f, 0.06f, 0.035f)
        Kind.BOOKS -> Triple(0.85f, 0.85f, 0.85f)
        Kind.BOOK -> Triple(0.32f, 0.11f, 0.08f)
        Kind.TABLE -> Triple(0.12f, 0.07f, 0.04f)
        Kind.MUG -> Triple(0.72f, 0.69f, 0.63f)
        Kind.CANDLE -> Triple(0.86f, 0.80f, 0.66f)
        Kind.FLAME -> Triple(1.0f, 0.66f, 0.24f)
        Kind.CUSHION -> Triple(0.52f, 0.36f, 0.10f)
        Kind.THROW -> Triple(0.55f, 0.52f, 0.46f)
        Kind.POT -> Triple(0.50f, 0.28f, 0.18f)
        Kind.STEM -> Triple(0.12f, 0.08f, 0.05f)
        Kind.LEAF -> Triple(0.07f, 0.17f, 0.06f)
        Kind.FRAME -> Triple(0.04f, 0.035f, 0.03f)
        Kind.ART_ABSTRACT, Kind.ART_LANDSCAPE -> Triple(0.9f, 0.9f, 0.9f)
        Kind.LOG -> Triple(0.16f, 0.10f, 0.06f)
        Kind.EMBER -> Triple(0.95f, 0.28f, 0.05f)
        Kind.SPEAKER -> Triple(0.05f, 0.045f, 0.04f)
        Kind.GRILLE -> Triple(0.022f, 0.022f, 0.026f)
        Kind.PENDANT_CORD -> Triple(0.02f, 0.02f, 0.02f)
        Kind.PENDANT -> Triple(1.0f, 0.78f, 0.5f)
        Kind.VASE -> Triple(0.30f, 0.38f, 0.34f)
    }

    /** How much of the film's light a kind catches: what faces the screen most (the back wall, the sofa) most. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.BACK_WALL -> 0.6f
        Kind.SOFA -> 0.55f
        Kind.FLOOR, Kind.STEP, Kind.RUG -> 0.45f
        Kind.WALL -> 0.35f
        Kind.CEILING, Kind.BEAM, Kind.CHIMNEY, Kind.HEARTH, Kind.MANTEL -> 0.3f
        Kind.LAMP_STAND -> 0.2f
        Kind.MULLION, Kind.CREDENZA -> 0.1f
        Kind.FRONT_WALL, Kind.FIN -> 0.05f
        Kind.FIRE, Kind.LAMP -> 0f
        Kind.CUSHION, Kind.THROW, Kind.TABLE, Kind.BOOK, Kind.MUG -> 0.45f
        Kind.SHELF, Kind.BOOKS, Kind.VASE, Kind.FRAME, Kind.ART_ABSTRACT -> 0.55f
        Kind.POT, Kind.STEM, Kind.LEAF, Kind.CANDLE, Kind.LOG, Kind.ART_LANDSCAPE -> 0.3f
        Kind.SPEAKER, Kind.GRILLE, Kind.PENDANT_CORD -> 0.1f
        Kind.FLAME, Kind.EMBER, Kind.PENDANT -> 0f
    }

    /**
     * A part's colour with the lights at [level] (1 up, about 0.12 during a
     * film) and the film's [tint] on it. The fire burns on; the lamp goes down
     * with the lights, to half.
     */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> {
        val base = baseColour(kind)
        return when (kind) {
            Kind.FIRE, Kind.FLAME, Kind.EMBER -> base
            Kind.LAMP, Kind.PENDANT -> (0.5f + 0.5f * level).let { k -> Triple(base.first * k, base.second * k, base.third * k) }
            else -> houseLit(base, spill(kind), level, tint)
        }
    }

    /** What each kind is made of: oak boards underfoot, timber, stone, wool and cloth, books, two pictures. */
    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.FLOOR, Kind.STEP -> Surface(R.drawable.lumiere_tex_planks, 1.6f, 0.8f)
        Kind.WALL, Kind.BACK_WALL, Kind.CEILING -> Surface(R.drawable.lumiere_tex_wood, 1.6f, 1.6f)
        Kind.BEAM, Kind.FIN, Kind.CREDENZA, Kind.MANTEL, Kind.SHELF, Kind.TABLE, Kind.LOG, Kind.SPEAKER -> Surface(R.drawable.lumiere_tex_wood, 0.9f, 0.9f)
        Kind.RUG -> Surface(R.drawable.lumiere_tex_rug, 0f, 0f)
        Kind.SOFA, Kind.CUSHION, Kind.THROW -> Surface(R.drawable.lumiere_tex_fabric, 0.5f, 0.5f)
        Kind.CHIMNEY, Kind.HEARTH -> Surface(R.drawable.lumiere_tex_stone, 1.2f, 1.2f)
        Kind.BOOKS -> Surface(R.drawable.lumiere_tex_books, 0.9f, 0f)
        Kind.ART_ABSTRACT -> Surface(R.drawable.lumiere_tex_art_abstract, 0f, 0f)
        Kind.ART_LANDSCAPE -> Surface(R.drawable.lumiere_tex_art_landscape, 0f, 0f)
        else -> null
    }

    /** What moves: the flames, on the logs and the candles. */
    fun moves(kind: Kind, i: Int, t: Float): Life.Sway? = if (kind == Kind.FLAME) Life.flame(i, t) else null
}
