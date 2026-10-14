package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The Moon: you stand on a lunar base's observation deck, a tread-plate
 * platform on legs over the regolith (the sky), the screen standing out on
 * the surface before you and the Earth hanging over the horizon. The deck
 * runs out ahead and stops where your sightline to the screen's foot comes
 * down to its edge; everything taller — safety rails, equipment cases, a
 * rack of oxygen bottles, a toolbox, work lights, a mast with a dish and a
 * beacon blinking on top — is beside you or behind.
 *
 * Laid out in your seat's own frame as Auditorium is: you at the origin on
 * the deck (y = 0), facing +Z, your left +X. Pure, so it's tested without a
 * headset; a Scenery turns it into entities.
 */
object MoonBase {
    enum class Kind { DECK, FRAME, LEG, POST, RAIL, CASE, CASE_LID, BOTTLE, RACK, TOOLBOX, LIGHT_POST, LIGHT, MAST, DISH, BEACON, CABLE }

    const val HALF_WIDTH = 2.0f
    const val BEHIND = 2.6f
    const val AHEAD = 4.0f
    /** However big the screen, the deck reaches this far before you: room for your feet. */
    const val MIN_AHEAD = 0.3f
    const val LIP = 0.06f
    private const val CLEARANCE = 0.05f
    private const val RAIL_TOP = 1.05f

    fun build(eyeY: Float, footSlope: Float = 0f): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
        // Short of where your sightline comes down to the lip, less the frame's own depth beyond it.
        val ahead = if (footSlope <= 0f) AHEAD else ((eyeY - LIP - CLEARANCE) / footSlope - 0.12f).coerceIn(MIN_AHEAD, AHEAD)
        // The deck: tread-plate panels on a frame, the frame on four legs down into the dust.
        val length = ahead + BEHIND
        val panels = (length / 1.2f).roundToInt().coerceIn(3, 6)
        val pitch = length / panels
        for (i in 0 until panels) {
            val z0 = -BEHIND + i * pitch
            parts += Block.between(Kind.DECK, -HALF_WIDTH, HALF_WIDTH, -0.05f, 0f, z0 + 0.005f, z0 + pitch - 0.005f)
        }
        for (side in floatArrayOf(1f, -1f)) {
            val (x0, x1) = min(side * HALF_WIDTH, side * (HALF_WIDTH + 0.12f)) to max(side * HALF_WIDTH, side * (HALF_WIDTH + 0.12f))
            parts += Block.between(Kind.FRAME, x0, x1, -0.25f, LIP, -BEHIND - 0.12f, ahead + 0.12f)
            for (z in floatArrayOf(-BEHIND + 0.2f, ahead - 0.2f)) {
                val lx = side * (HALF_WIDTH - 0.1f)
                parts += Block.between(Kind.LEG, lx - 0.07f, lx + 0.07f, -1.6f, -0.25f, z - 0.07f, z + 0.07f)
            }
        }
        parts += Block.between(Kind.FRAME, -HALF_WIDTH, HALF_WIDTH, -0.25f, 0f, ahead, ahead + 0.12f)
        parts += Block.between(Kind.FRAME, -HALF_WIDTH, HALF_WIDTH, -0.25f, LIP, -BEHIND - 0.12f, -BEHIND)
        // Safety rails along the sides as far as your shoulder, and across the back.
        for (side in floatArrayOf(1f, -1f)) {
            val x = side * (HALF_WIDTH - 0.04f)
            for (z in floatArrayOf(-BEHIND + 0.05f, -1.3f, 0f)) parts += Block.between(Kind.POST, x - 0.03f, x + 0.03f, 0f, RAIL_TOP, z - 0.03f, z + 0.03f)
            parts += Block.between(Kind.RAIL, x - 0.03f, x + 0.03f, RAIL_TOP, RAIL_TOP + 0.05f, -BEHIND + 0.02f, 0.03f)
            parts += Block.between(Kind.RAIL, x - 0.025f, x + 0.025f, 0.55f, 0.59f, -BEHIND + 0.02f, 0.03f)
        }
        parts += Block.between(Kind.RAIL, -HALF_WIDTH, HALF_WIDTH, RAIL_TOP, RAIL_TOP + 0.05f, -BEHIND + 0.01f, -BEHIND + 0.08f)

        // Equipment behind you: two cases, a rack of oxygen bottles, a toolbox, a coil of cable.
        parts += Block.between(Kind.CASE, 0.9f, 1.6f, 0f, 0.42f, -2.35f, -1.85f)
        parts += Block.between(Kind.CASE_LID, 0.88f, 1.62f, 0.42f, 0.46f, -2.37f, -1.83f)
        parts += Block.between(Kind.CASE, 1.0f, 1.5f, 0.46f, 0.76f, -2.3f, -1.95f)
        parts += Block.between(Kind.RACK, -1.75f, -1.05f, 0f, 1.2f, -2.5f, -2.42f)
        for (k in 0 until 3) {
            val x = -1.65f + k * 0.23f
            parts += Block.between(Kind.BOTTLE, x - 0.08f, x + 0.08f, 0.05f, 1.1f, -2.4f, -2.24f)
        }
        parts += Block.between(Kind.TOOLBOX, -1.6f, -1.1f, 0f, 0.24f, -1.4f, -1.15f)
        parts += Block.between(Kind.CABLE, -0.5f, -0.1f, 0f, 0.06f, -2.2f, -1.8f)
        // Work lights on posts at the back corners, a mast with its dish and a slow beacon behind you on the left.
        for (side in floatArrayOf(1f, -1f)) {
            val x = side * (HALF_WIDTH - 0.15f)
            parts += Block.between(Kind.LIGHT_POST, x - 0.03f, x + 0.03f, 0f, 1.7f, -BEHIND + 0.1f, -BEHIND + 0.16f)
            parts += Block.between(Kind.LIGHT, x - 0.12f, x + 0.12f, 1.7f, 1.82f, -BEHIND + 0.08f, -BEHIND + 0.26f)
        }
        parts += Block.between(Kind.MAST, 0.45f, 0.53f, 0f, 2.6f, -2.5f, -2.42f)
        parts += Block.between(Kind.DISH, 0.2f, 0.78f, 2.3f, 2.85f, -2.4f, -2.32f)
        parts += Block.between(Kind.BEACON, 0.45f, 0.53f, 2.6f, 2.68f, -2.5f, -2.42f)
        return parts
    }

    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.DECK -> Triple(0.40f, 0.40f, 0.42f)
        Kind.FRAME, Kind.LEG -> Triple(0.20f, 0.20f, 0.22f)
        Kind.POST, Kind.RAIL -> Triple(0.62f, 0.50f, 0.08f)
        Kind.CASE -> Triple(0.72f, 0.72f, 0.70f)
        Kind.CASE_LID -> Triple(0.55f, 0.22f, 0.08f)
        Kind.BOTTLE -> Triple(0.30f, 0.42f, 0.55f)
        Kind.RACK -> Triple(0.25f, 0.25f, 0.27f)
        Kind.TOOLBOX -> Triple(0.55f, 0.12f, 0.08f)
        Kind.LIGHT_POST, Kind.MAST -> Triple(0.30f, 0.30f, 0.32f)
        Kind.LIGHT -> Triple(1.0f, 0.95f, 0.85f)
        Kind.DISH -> Triple(0.80f, 0.80f, 0.78f)
        Kind.BEACON -> Triple(1.0f, 0.15f, 0.08f)
        Kind.CABLE -> Triple(0.08f, 0.08f, 0.09f)
    }

    fun spill(kind: Kind): Float = when (kind) {
        Kind.LIGHT, Kind.BEACON -> 0f
        Kind.DECK, Kind.CASE, Kind.DISH -> 0.45f
        else -> 0.3f
    }

    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> = when (kind) {
        Kind.BEACON -> baseColour(kind)
        // The work lights go down for the film, to a glow.
        Kind.LIGHT -> (0.25f + 0.75f * level).let { k -> baseColour(kind).let { (r, g, b) -> Triple(r * k, g * k, b * k) } }
        else -> houseLit(baseColour(kind), spill(kind), level, tint)
    }

    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.DECK -> Surface(R.drawable.lumiere_tex_grating, 1.0f, 1.0f)
        Kind.CASE, Kind.RACK -> Surface(R.drawable.lumiere_tex_hull, 0.6f, 0.6f)
        else -> null
    }

    /** What moves: the beacon on the mast, a slow red blink. */
    fun moves(kind: Kind, i: Int, t: Float): Life.Sway? = if (kind == Kind.BEACON) Life.blink(t, 2.0f, 0.15f) else null
}
