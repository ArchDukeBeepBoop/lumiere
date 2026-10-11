package app.lumiere.android.spatial

import kotlin.math.roundToInt

/**
 * The lakeside's pontoon under you, as a list of boxes: a weathered timber
 * deck at your floor, its planks laid across with gaps the water shows
 * through, a low beam along each edge, short posts under it, an iron bollard
 * at each far corner and a lantern on a post at each corner behind you. No
 * water: the sky's lake is all round and under you, and a plane would hide
 * it. About twenty-five boxes.
 *
 * The deck reaches up to five metres ahead, but stops where your sightline
 * to the screen's foot comes down to a bollard's height, so a big screen's
 * lower edge, and the captions over it, are never behind the boards.
 *
 * Laid out in your seat's own frame as Auditorium is: you at the origin on
 * the real floor (the deck's top, y = 0), facing +Z, your left +X. Pure, so
 * it's tested without a headset; a Scenery turns it into entities.
 */
object Dock {
    enum class Kind { PLANK, PLANK_WORN, BEAM, POST, BOLLARD, LANTERN_POST, LANTERN }

    const val HALF_WIDTH = 1.5f
    const val BEHIND = 1.5f
    const val AHEAD = 5f
    /** However big the screen, the deck reaches this far before you: room for your feet. */
    const val MIN_AHEAD = 0.6f
    const val BOLLARD_HEIGHT = 0.3f
    private const val PLANK = 0.06f
    private const val GAP = 0.025f
    private const val BEAM_WIDTH = 0.12f
    /** The edge beams stand this proud of the deck: a low kerb. */
    private const val KERB = 0.08f
    private const val CLEARANCE = 0.05f

    /**
     * The pontoon for eyes at [eyeY], with your sightline to the screen's
     * foot coming down [footSlope] metres for each metre ahead
     * (TheaterGeometry.footSlope); 0 when there's no screen to keep clear.
     */
    fun build(eyeY: Float, footSlope: Float = 0f): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
        val ahead = if (footSlope <= 0f) AHEAD
            else ((eyeY - BOLLARD_HEIGHT - CLEARANCE) / footSlope).coerceIn(MIN_AHEAD, AHEAD)
        // Planks across the deck, about 60 cm each, every third a shade more worn; the gaps show the water.
        val length = ahead + BEHIND
        val planks = (length / 0.6f).roundToInt().coerceIn(8, 12)
        val pitch = length / planks
        for (i in 0 until planks) {
            val z0 = -BEHIND + i * pitch
            parts += Block.between(if (i % 3 == 1) Kind.PLANK_WORN else Kind.PLANK,
                -HALF_WIDTH, HALF_WIDTH, -PLANK, 0f, z0 + GAP / 2, z0 + pitch - GAP / 2)
        }
        for (side in floatArrayOf(1f, -1f)) {
            val inner = side * HALF_WIDTH
            val outer = side * (HALF_WIDTH + BEAM_WIDTH)
            val middle = (inner + outer) / 2
            // The edge beam the planks rest on, a low kerb along the deck.
            parts += Block.between(Kind.BEAM, minOf(inner, outer), maxOf(inner, outer), -0.25f, KERB, -BEHIND, ahead)
            // Short posts under it, down toward the water.
            for (z in floatArrayOf(-BEHIND + 0.25f, (ahead - BEHIND) / 2, ahead - 0.25f))
                parts += Block.between(Kind.POST, middle - 0.08f, middle + 0.08f, -0.75f, -0.25f, z - 0.08f, z + 0.08f)
            // An iron bollard at the far corner, low enough to stay under your sightline.
            val bx = side * (HALF_WIDTH - 0.22f)
            parts += Block.between(Kind.BOLLARD, bx - 0.1f, bx + 0.1f, 0f, BOLLARD_HEIGHT, ahead - 0.32f, ahead - 0.12f)
            // A lantern on a post at the corner behind you, out of the way of the screen.
            val lx = side * (HALF_WIDTH - 0.12f)
            val lz = -BEHIND + 0.12f
            parts += Block.between(Kind.LANTERN_POST, lx - 0.04f, lx + 0.04f, 0f, 1.0f, lz - 0.04f, lz + 0.04f)
            parts += Block.between(Kind.LANTERN, lx - 0.09f, lx + 0.09f, 1.0f, 1.24f, lz - 0.09f, lz + 0.09f)
        }
        return parts
    }

    /** Each kind's colour at dusk with the lights up, linear 0..1: silvered timber, dark iron, a warm flame. */
    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.PLANK -> Triple(0.20f, 0.17f, 0.135f)
        Kind.PLANK_WORN -> Triple(0.165f, 0.14f, 0.115f)
        Kind.BEAM -> Triple(0.11f, 0.085f, 0.065f)
        Kind.POST -> Triple(0.07f, 0.055f, 0.045f)
        Kind.BOLLARD, Kind.LANTERN_POST -> Triple(0.035f, 0.035f, 0.04f)
        Kind.LANTERN -> Triple(1.0f, 0.68f, 0.32f)
    }

    /** How much of the film's light a kind catches: the deck most, the posts in its shadow least. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.PLANK, Kind.PLANK_WORN -> 0.45f
        Kind.BEAM, Kind.BOLLARD, Kind.LANTERN_POST -> 0.3f
        Kind.POST -> 0.1f
        Kind.LANTERN -> 0f
    }

    /** A part's colour with the lights at [level] and the film's [tint] on it; the lanterns burn on. */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> =
        if (kind == Kind.LANTERN) baseColour(kind) else houseLit(baseColour(kind), spill(kind), level, tint)
}
