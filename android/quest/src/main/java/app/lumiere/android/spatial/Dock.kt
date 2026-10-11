package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The lakeside's pontoon under you, as a list of boxes: a weathered timber
 * deck at your floor, its planks laid across with gaps the water shows
 * through, a low beam along each edge, short posts under it, an iron bollard
 * at each far corner and a lantern on a post at each corner behind you, and
 * someone's evening on it (see evening). No water: the sky's lake is all
 * round and under you, and a plane would hide it.
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
    enum class Kind {
        PLANK, PLANK_WORN, BEAM, POST, BOLLARD, LANTERN_POST, LANTERN,
        // An evening someone is spending here: two chairs and a crate between them with mugs and a jar
        // candle, a rod and its tackle, a cool box, a coil of rope, a rowing boat tied alongside, a
        // string of bulbs behind you, the lanterns' flames, and fireflies over the water.
        CHAIR, CRATE, MUG, JAR, FLAME, ROD, TACKLE, COOLER, COOLER_LID, ROPE, HULL, HULL_INSIDE, THWART, OAR, BULB, FIREFLY,
    }

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
            // Its flame on the glass's side toward you.
            parts += Block.between(Kind.FLAME, lx - 0.02f, lx + 0.02f, 1.04f, 1.12f, lz + 0.09f, lz + 0.1f)
            // A coil of rope by the far bollard.
            val rx = side * (HALF_WIDTH - 0.55f)
            parts += Block.between(Kind.ROPE, rx - 0.16f, rx + 0.16f, 0f, 0.04f, ahead - 0.42f, ahead - 0.1f)
        }
        evening(parts)
        return parts
    }

    /**
     * Someone's evening on the pontoon, all of it beside or behind you and
     * low, so nothing reaches into your view of the screen: a chair either
     * side of you with a crate between them (two mugs, a jar candle), a rod
     * in its holder and the tackle box at your left, a cool box behind, a
     * rowing boat tied alongside on your right, a string of bulbs between the
     * lantern posts, and fireflies over the water round about.
     */
    private fun evening(parts: MutableList<Block<Kind>>) {
        for (side in floatArrayOf(1f, -1f)) {
            fun across(a: Float, b: Float) = min(side * a, side * b) to max(side * a, side * b)
            val (x0, x1) = across(0.78f, 1.32f)
            parts += Block.between(Kind.CHAIR, x0, x1, 0.32f, 0.37f, -1.05f, -0.5f)                    // seat
            parts += Block.between(Kind.CHAIR, x0, x1, 0.37f, 0.98f, -1.13f, -1.05f)                   // back
            val (a0, a1) = across(0.72f, 0.8f); val (b0, b1) = across(1.3f, 1.38f)
            parts += Block.between(Kind.CHAIR, a0, a1, 0.56f, 0.6f, -1.08f, -0.42f)                    // arms
            parts += Block.between(Kind.CHAIR, b0, b1, 0.56f, 0.6f, -1.08f, -0.42f)
            parts += Block.between(Kind.CHAIR, x0, x1, 0f, 0.32f, -0.56f, -0.5f)                       // legs, front
            parts += Block.between(Kind.CHAIR, x0, x1, 0f, 0.32f, -1.05f, -0.99f)                      // and back
        }
        // The crate between the chairs, behind you: two mugs and a jar with a candle in it.
        parts += Block.between(Kind.CRATE, -0.24f, 0.24f, 0f, 0.42f, -1.32f, -0.88f)
        parts += Block.between(Kind.MUG, -0.16f, -0.08f, 0.42f, 0.52f, -1.2f, -1.12f)
        parts += Block.between(Kind.MUG, 0.1f, 0.18f, 0.42f, 0.52f, -1.05f, -0.97f)
        parts += Block.between(Kind.JAR, -0.04f, 0.04f, 0.42f, 0.54f, -1.04f, -0.96f)
        parts += Block.between(Kind.FLAME, -0.01f, 0.01f, 0.5f, 0.56f, -1.01f, -0.99f)
        // A rod upright in its holder at the kerb on your left, and its tackle box.
        parts += Block.between(Kind.ROD, 1.43f, 1.45f, 0f, 1.85f, 0.29f, 0.31f)
        parts += Block.between(Kind.TACKLE, 1.0f, 1.36f, 0f, 0.18f, 0.02f, 0.24f)
        // A cool box behind the left chair, its lid a lighter band.
        parts += Block.between(Kind.COOLER, 0.82f, 1.3f, 0f, 0.34f, -1.48f, -1.2f)
        parts += Block.between(Kind.COOLER_LID, 0.8f, 1.32f, 0.34f, 0.4f, -1.5f, -1.18f)
        // A rowing boat tied alongside on your right, low on the water and back from your view of the screen.
        val bx0 = -HALF_WIDTH - BEAM_WIDTH - 0.98f; val bx1 = -HALF_WIDTH - BEAM_WIDTH - 0.18f
        val bz0 = -2.6f; val bz1 = 0.4f
        parts += Block.between(Kind.HULL, bx0, bx1, -0.58f, -0.5f, bz0 + 0.1f, bz1 - 0.1f)
        parts += Block.between(Kind.HULL, bx0, bx0 + 0.06f, -0.58f, -0.18f, bz0, bz1)
        parts += Block.between(Kind.HULL, bx1 - 0.06f, bx1, -0.58f, -0.18f, bz0, bz1)
        parts += Block.between(Kind.HULL, bx0, bx1, -0.58f, -0.2f, bz0, bz0 + 0.07f)
        parts += Block.between(Kind.HULL, bx0, bx1, -0.58f, -0.22f, bz1 - 0.07f, bz1)
        parts += Block.between(Kind.HULL_INSIDE, bx0 + 0.06f, bx1 - 0.06f, -0.5f, -0.49f, bz0 + 0.07f, bz1 - 0.07f)
        for (z in floatArrayOf(-1.7f, -0.5f)) parts += Block.between(Kind.THWART, bx0 + 0.06f, bx1 - 0.06f, -0.34f, -0.3f, z - 0.12f, z + 0.12f)
        for (x in floatArrayOf(bx0 + 0.2f, bx1 - 0.2f)) parts += Block.between(Kind.OAR, x - 0.03f, x + 0.03f, -0.3f, -0.27f, bz0 + 0.2f, bz1 - 0.3f)
        // A string of bulbs between the lantern posts behind you, sagging in the middle.
        val bz = -BEHIND + 0.12f
        for (k in 0 until 9) {
            val x = -1.2f + k * 0.3f
            val y = 1.32f - 0.2f * (1 - (x / 1.38f) * (x / 1.38f))
            parts += Block.between(Kind.BULB, x - 0.025f, x + 0.025f, y - 0.05f, y, bz - 0.025f, bz + 0.025f)
        }
        // Fireflies over the water, either side and behind: each wanders from here (Life.firefly).
        val homes = listOf(
            floatArrayOf(2.2f, 0.6f, -0.6f), floatArrayOf(2.8f, 1.1f, 0.2f), floatArrayOf(3.4f, 0.5f, -1.4f), floatArrayOf(2.5f, 1.4f, -2.2f),
            floatArrayOf(3.9f, 0.9f, -0.2f), floatArrayOf(2.1f, 0.4f, -2.9f), floatArrayOf(3.1f, 1.6f, -3.3f), floatArrayOf(4.4f, 0.7f, -1.9f),
            floatArrayOf(-3.1f, 0.8f, -0.9f), floatArrayOf(-3.6f, 1.3f, -2.1f), floatArrayOf(-4.2f, 0.5f, -0.3f), floatArrayOf(-3.0f, 1.5f, -3.0f),
            floatArrayOf(-4.6f, 1.0f, -1.5f), floatArrayOf(-2.9f, 0.4f, 0.4f), floatArrayOf(1.2f, 1.7f, -3.6f), floatArrayOf(-1.0f, 1.2f, -3.8f),
            floatArrayOf(0.3f, 0.6f, -4.2f), floatArrayOf(-2.2f, 1.8f, -4.0f),
        )
        for ((x, y, z) in homes) parts += Block.between(Kind.FIREFLY, x - 0.012f, x + 0.012f, y - 0.012f, y + 0.012f, z - 0.012f, z + 0.012f)
    }

    /** Each kind's colour at dusk with the lights up, linear 0..1: silvered timber, dark iron, a warm flame. */
    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.PLANK -> Triple(0.20f, 0.17f, 0.135f)
        Kind.PLANK_WORN -> Triple(0.165f, 0.14f, 0.115f)
        Kind.BEAM -> Triple(0.11f, 0.085f, 0.065f)
        Kind.POST -> Triple(0.07f, 0.055f, 0.045f)
        Kind.BOLLARD, Kind.LANTERN_POST -> Triple(0.035f, 0.035f, 0.04f)
        Kind.LANTERN -> Triple(1.0f, 0.68f, 0.32f)
        Kind.CHAIR -> Triple(0.30f, 0.36f, 0.34f)
        Kind.CRATE -> Triple(0.22f, 0.16f, 0.10f)
        Kind.MUG -> Triple(0.55f, 0.18f, 0.12f)
        Kind.JAR -> Triple(0.45f, 0.40f, 0.30f)
        Kind.FLAME -> Triple(1.0f, 0.66f, 0.24f)
        Kind.ROD -> Triple(0.05f, 0.05f, 0.05f)
        Kind.TACKLE -> Triple(0.10f, 0.20f, 0.12f)
        Kind.COOLER -> Triple(0.42f, 0.10f, 0.08f)
        Kind.COOLER_LID -> Triple(0.6f, 0.58f, 0.54f)
        Kind.ROPE -> Triple(0.36f, 0.30f, 0.20f)
        Kind.HULL -> Triple(0.07f, 0.16f, 0.13f)
        Kind.HULL_INSIDE -> Triple(0.20f, 0.15f, 0.10f)
        Kind.THWART, Kind.OAR -> Triple(0.24f, 0.17f, 0.10f)
        Kind.BULB -> Triple(1.0f, 0.82f, 0.52f)
        Kind.FIREFLY -> Triple(0.85f, 1.0f, 0.42f)
    }

    /** How much of the film's light a kind catches: the deck most, the posts in its shadow least. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.PLANK, Kind.PLANK_WORN -> 0.45f
        Kind.BEAM, Kind.BOLLARD, Kind.LANTERN_POST -> 0.3f
        Kind.POST -> 0.1f
        Kind.LANTERN, Kind.FLAME, Kind.BULB, Kind.FIREFLY -> 0f
        Kind.CHAIR, Kind.CRATE, Kind.MUG, Kind.JAR, Kind.TACKLE, Kind.COOLER, Kind.COOLER_LID, Kind.ROPE -> 0.4f
        Kind.ROD, Kind.HULL, Kind.HULL_INSIDE, Kind.THWART, Kind.OAR -> 0.25f
    }

    /** A part's colour with the lights at [level] and the film's [tint] on it; the lanterns burn on. */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> = when (kind) {
        Kind.LANTERN, Kind.FLAME, Kind.FIREFLY -> baseColour(kind)
        // The bulbs go down with the lights, to half, as the cabin's lamps do.
        Kind.BULB -> (0.5f + 0.5f * level).let { k -> baseColour(kind).let { (r, g, b) -> Triple(r * k, g * k, b * k) } }
        else -> houseLit(baseColour(kind), spill(kind), level, tint)
    }

    /** What each kind is made of: silvered boards, timber, and the painted boat's planking. */
    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.PLANK, Kind.PLANK_WORN -> Surface(R.drawable.lumiere_tex_weathered, 1.2f, 0f)
        Kind.BEAM, Kind.POST, Kind.CHAIR, Kind.CRATE, Kind.HULL, Kind.HULL_INSIDE, Kind.THWART, Kind.OAR -> Surface(R.drawable.lumiere_tex_wood, 0.9f, 0.9f)
        Kind.ROPE -> Surface(R.drawable.lumiere_tex_fabric, 0.2f, 0.2f)
        else -> null
    }

    /** What moves: the flames in the lanterns and the jar, and the fireflies. */
    fun moves(kind: Kind, i: Int, t: Float): Life.Sway? = when (kind) {
        Kind.FLAME -> Life.flame(i, t)
        Kind.FIREFLY -> Life.firefly(i, t)
        else -> null
    }
}
