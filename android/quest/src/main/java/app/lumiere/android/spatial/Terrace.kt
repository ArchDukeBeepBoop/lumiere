package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Above the clouds: a teak terrace afloat over the cloud sea (the sky), the
 * screen hanging in the air before you. Its deck runs out ahead of you and
 * stops where your sightline to the screen's foot comes down to its edge, as
 * the lakeside's pontoon does; everything taller — the rails, two
 * loungers and the low table between them with two drinks on it, olive
 * trees in planters, lanterns — stands beside you or behind, never in front.
 * No floor beyond the deck: the clouds are all round and below.
 *
 * Laid out in your seat's own frame as Auditorium is: you at the origin on
 * the deck (y = 0), facing +Z, your left +X. Pure, so it's tested without a
 * headset; a Scenery turns it into entities.
 */
object Terrace {
    enum class Kind { DECK, EDGE, POST, RAIL, LOUNGER, CUSHION, TABLE, GLASS, DRINK, PLANTER, TRUNK, OLIVE, LANTERN, FLAME, RUG }

    const val HALF_WIDTH = 2.4f
    const val BEHIND = 2.4f
    const val AHEAD = 4.5f
    /** However big the screen, the deck reaches this far before you: room for your feet. */
    const val MIN_AHEAD = 0.3f
    /** The deck's front lip, all that stands above it before you. */
    const val LIP = 0.05f
    private const val CLEARANCE = 0.05f
    private const val RAIL_TOP = 1.0f
    private const val FRONT_BEAM = 0.08f

    /** The terrace for eyes at [eyeY], your sightline to the screen's foot coming down [footSlope] a metre ahead. */
    fun build(eyeY: Float, footSlope: Float = 0f): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
        // Short of where your sightline comes down to the lip, less the front beam's own depth beyond it.
        val ahead = if (footSlope <= 0f) AHEAD else ((eyeY - LIP - CLEARANCE) / footSlope - FRONT_BEAM).coerceIn(MIN_AHEAD, AHEAD)
        // The deck: teak boards across it, a narrow gap between each.
        val length = ahead + BEHIND
        val boards = (length / 0.5f).roundToInt().coerceIn(8, 14)
        val pitch = length / boards
        for (i in 0 until boards) {
            val z0 = -BEHIND + i * pitch
            parts += Block.between(Kind.DECK, -HALF_WIDTH, HALF_WIDTH, -0.06f, 0f, z0 + 0.01f, z0 + pitch - 0.01f)
        }
        // Its edges: a dark beam under each side and the front, the front only a lip.
        for (side in floatArrayOf(1f, -1f)) {
            val (x0, x1) = min(side * HALF_WIDTH, side * (HALF_WIDTH + 0.1f)) to max(side * HALF_WIDTH, side * (HALF_WIDTH + 0.1f))
            parts += Block.between(Kind.EDGE, x0, x1, -0.3f, LIP, -BEHIND - 0.1f, ahead)
        }
        parts += Block.between(Kind.EDGE, -HALF_WIDTH, HALF_WIDTH, -0.3f, 0f, ahead, ahead + FRONT_BEAM)
        parts += Block.between(Kind.EDGE, -HALF_WIDTH - 0.1f, HALF_WIDTH + 0.1f, -0.3f, LIP, -BEHIND - 0.1f, -BEHIND)
        // Rails along both sides as far as your shoulder, and across the back: posts and a top rail.
        for (side in floatArrayOf(1f, -1f)) {
            val x = side * (HALF_WIDTH - 0.04f)
            for (z in floatArrayOf(-BEHIND + 0.05f, -1.2f, 0f)) parts += Block.between(Kind.POST, x - 0.03f, x + 0.03f, 0f, RAIL_TOP, z - 0.03f, z + 0.03f)
            parts += Block.between(Kind.RAIL, x - 0.035f, x + 0.035f, RAIL_TOP, RAIL_TOP + 0.04f, -BEHIND + 0.02f, 0.03f)
        }
        for (x in floatArrayOf(-0.8f, 0.8f)) parts += Block.between(Kind.POST, x - 0.03f, x + 0.03f, 0f, RAIL_TOP, -BEHIND + 0.02f, -BEHIND + 0.08f)
        parts += Block.between(Kind.RAIL, -HALF_WIDTH, HALF_WIDTH, RAIL_TOP, RAIL_TOP + 0.04f, -BEHIND + 0.01f, -BEHIND + 0.09f)

        // An outdoor rug behind you, two loungers on it facing the screen, a low table between them with two drinks.
        parts += Block.between(Kind.RUG, -1.9f, 1.9f, 0f, 0.012f, -2.1f, -0.3f)
        for (side in floatArrayOf(1f, -1f)) {
            val (x0, x1) = min(side * 0.9f, side * 1.6f) to max(side * 0.9f, side * 1.6f)
            parts += Block.between(Kind.LOUNGER, x0, x1, 0f, 0.28f, -2.05f, -0.35f)
            parts += Block.between(Kind.CUSHION, x0 + 0.03f, x1 - 0.03f, 0.28f, 0.34f, -1.6f, -0.4f)
            parts += Block.between(Kind.CUSHION, x0 + 0.03f, x1 - 0.03f, 0.28f, 0.72f, -2.0f, -1.6f)
        }
        parts += Block.between(Kind.TABLE, -0.3f, 0.3f, 0.36f, 0.4f, -1.5f, -1.0f)
        parts += Block.between(Kind.TABLE, -0.24f, 0.24f, 0f, 0.36f, -1.44f, -1.06f)
        for ((x, z) in listOf(-0.12f to -1.3f, 0.1f to -1.18f)) {
            parts += Block.between(Kind.GLASS, x - 0.035f, x + 0.035f, 0.4f, 0.56f, z - 0.035f, z + 0.035f)
            parts += Block.between(Kind.DRINK, x - 0.03f, x + 0.03f, 0.41f, 0.5f, z - 0.03f, z + 0.03f)
        }
        // An olive tree in a planter at each back corner, a lantern beside each lounger.
        for (side in floatArrayOf(1f, -1f)) {
            val px = side * (HALF_WIDTH - 0.45f); val pz = -BEHIND + 0.45f
            parts += Block.between(Kind.PLANTER, px - 0.3f, px + 0.3f, 0f, 0.55f, pz - 0.3f, pz + 0.3f)
            parts += Block.between(Kind.TRUNK, px - 0.04f, px + 0.04f, 0.55f, 1.35f, pz - 0.04f, pz + 0.04f)
            parts += Block.between(Kind.OLIVE, px - 0.38f, px + 0.38f, 1.25f, 1.75f, pz - 0.36f, pz + 0.36f)
            parts += Block.between(Kind.OLIVE, px - 0.24f + side * 0.12f, px + 0.24f + side * 0.12f, 1.6f, 1.95f, pz - 0.22f, pz + 0.26f)
            val lx = side * 1.85f
            parts += Block.between(Kind.LANTERN, lx - 0.1f, lx + 0.1f, 0f, 0.36f, -0.7f, -0.5f)
            parts += Block.between(Kind.FLAME, lx - 0.015f, lx + 0.015f, 0.12f, 0.2f, -0.49f, -0.48f)
        }
        return parts
    }

    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.DECK -> Triple(0.30f, 0.18f, 0.09f)
        Kind.EDGE -> Triple(0.10f, 0.07f, 0.05f)
        Kind.POST, Kind.RAIL -> Triple(0.10f, 0.10f, 0.11f)
        Kind.LOUNGER -> Triple(0.24f, 0.15f, 0.08f)
        Kind.CUSHION -> Triple(0.72f, 0.68f, 0.60f)
        Kind.TABLE -> Triple(0.20f, 0.12f, 0.06f)
        Kind.GLASS -> Triple(0.55f, 0.6f, 0.62f)
        Kind.DRINK -> Triple(0.85f, 0.45f, 0.12f)
        Kind.PLANTER -> Triple(0.42f, 0.40f, 0.36f)
        Kind.TRUNK -> Triple(0.20f, 0.15f, 0.10f)
        Kind.OLIVE -> Triple(0.16f, 0.22f, 0.12f)
        Kind.LANTERN -> Triple(0.05f, 0.05f, 0.05f)
        Kind.FLAME -> Triple(1.0f, 0.68f, 0.28f)
        Kind.RUG -> Triple(0.45f, 0.40f, 0.33f)
    }

    fun spill(kind: Kind): Float = when (kind) {
        Kind.FLAME -> 0f
        Kind.DECK, Kind.CUSHION, Kind.RUG -> 0.45f
        else -> 0.3f
    }

    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> =
        if (kind == Kind.FLAME) baseColour(kind) else houseLit(baseColour(kind), spill(kind), level, tint)

    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.DECK -> Surface(R.drawable.lumiere_tex_wood, 1.6f, 0f)
        Kind.EDGE, Kind.LOUNGER, Kind.TABLE, Kind.TRUNK -> Surface(R.drawable.lumiere_tex_wood, 0.9f, 0.9f)
        Kind.CUSHION, Kind.RUG -> Surface(R.drawable.lumiere_tex_fabric, 0.5f, 0.5f)
        Kind.PLANTER -> Surface(R.drawable.lumiere_tex_stone, 0.8f, 0.8f)
        else -> null
    }

    fun moves(kind: Kind, i: Int, t: Float): Life.Sway? = if (kind == Kind.FLAME) Life.flame(i, t) else null
}
