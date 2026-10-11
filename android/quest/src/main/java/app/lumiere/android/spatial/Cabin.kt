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
 * you on a wool rug, and the back wall three metres behind you. At most
 * sixty boxes, flat-shaded.
 *
 * The screen is a wall 5.5 m across, so with a tall film or a near seat its
 * foot comes below your own floor. Then the great room is a step down
 * before you: you sit on a raised oak dais, and the floor under the screen
 * is low enough for the credenza beneath its foot. The dais's edge and every
 * step stay under your sightline to the screen's foot.
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
    }

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
        val low = 0f
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
        return parts
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
    }

    /** How much of the film's light a kind catches: what faces the screen most (the back wall, the sofa) most. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.BACK_WALL -> 0.01f
        Kind.SOFA -> 0.55f
        Kind.FLOOR, Kind.STEP, Kind.RUG -> 0.45f
        Kind.WALL -> 0.35f
        Kind.CEILING, Kind.BEAM, Kind.CHIMNEY, Kind.HEARTH, Kind.MANTEL -> 0.3f
        Kind.LAMP_STAND -> 0.2f
        Kind.MULLION, Kind.CREDENZA -> 0.1f
        Kind.FRONT_WALL, Kind.FIN -> 0.05f
        Kind.FIRE, Kind.LAMP -> 0f
    }

    /**
     * A part's colour with the lights at [level] (1 up, about 0.12 during a
     * film) and the film's [tint] on it. The fire burns on; the lamp goes down
     * with the lights, to half.
     */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> {
        val base = baseColour(kind)
        return when (kind) {
            Kind.FIRE -> base
            Kind.LAMP -> (0.5f + 0.5f * level).let { k -> Triple(base.first * k, base.second * k, base.third * k) }
            else -> houseLit(base, spill(kind), level, tint)
        }
    }
}
