package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min

/**
 * The space station: an observation module in low orbit, built round its
 * screen on the front bulkhead as the cabin is round its wall. White hull
 * panels and dark frames; windows down both sides from the floor up, a
 * window in the floor before you and a skylight over you, the Earth below
 * and the stars beyond (the sky). Handrails along the walls, status lights
 * along the ceiling and a few blinking on the back wall, lockers and the
 * hatch behind you, a photo stuck by it, a grow box of greens on your left,
 * a laptop on its arm at your right, cable runs, and a few things drifting
 * free — a notebook, a pen, a water pouch — as they do up there.
 *
 * Laid out in your seat's own frame as Auditorium is: you at the origin
 * (y = 0, your platform's top), facing +Z, your left +X; the screen's middle
 * at (0, [screenMiddleY], [distance]). Pure, so it's tested without a
 * headset; a Scenery turns it into entities.
 */
object Station {
    enum class Kind {
        FLOOR, PLATFORM, WALL, FRAME, FRONT, CEILING, HANDRAIL, STATUS, LED, SEAT, ARM, LAPTOP,
        GROW, GROW_LIGHT, LEAF, LOCKER, HATCH, PHOTO, CABLE, NOTEBOOK, PEN, POUCH,
    }

    const val HALF = 2.8f
    const val BEHIND = 2.4f
    const val SCREEN_GAP = 0.05f
    /** The most boxes the module may be: each a draw call. */
    const val MOST_BOXES = 120
    private const val WALL = 0.15f
    private const val SILL = 0.2f
    private const val LINTEL = 2.3f

    fun build(screenWidth: Float, screenHeight: Float, screenMiddleY: Float, distance: Float, eyeY: Float = 1.2f): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
        val screenBottom = screenMiddleY - screenHeight / 2
        val screenTop = screenMiddleY + screenHeight / 2
        val floor = min(0f, screenBottom - 0.15f)
        val ceiling = max(2.8f, screenTop + 0.3f)
        val wallFace = distance + SCREEN_GAP
        val front = wallFace + WALL
        val rear = -BEHIND - WALL

        // The floor: solid round your platform and along the sides, a window in it before you where there's room.
        val windowFrom = 0.6f; val windowTo = wallFace - 0.5f
        if (windowTo - windowFrom >= 0.6f) {
            parts += Block.between(Kind.FLOOR, -HALF, HALF, floor - 0.1f, floor, rear, windowFrom)
            parts += Block.between(Kind.FLOOR, -HALF, HALF, floor - 0.1f, floor, windowTo, front)
            for (side in floatArrayOf(1f, -1f))
                parts += Block.between(Kind.FLOOR, min(side * 1.6f, side * HALF), max(side * 1.6f, side * HALF), floor - 0.1f, floor, windowFrom, windowTo)
            var z = windowFrom + 0.7f
            while (z < windowTo - 0.2f) { parts += Block.between(Kind.FRAME, -1.6f, 1.6f, floor - 0.1f, floor, z - 0.04f, z + 0.04f); z += 0.7f }
        } else parts += Block.between(Kind.FLOOR, -HALF, HALF, floor - 0.1f, floor, rear, front)
        // Your platform, when the module's floor is lower than yours: you float over it on a padded step.
        if (floor < -0.05f) parts += Block.between(Kind.PLATFORM, -1.2f, 1.2f, floor, 0f, -1.4f, 0.5f)
        // The back wall and the front bulkhead the screen hangs on.
        parts += Block.between(Kind.WALL, -HALF - WALL, HALF + WALL, floor - 0.1f, ceiling + 0.1f, rear, -BEHIND)
        parts += Block.between(Kind.FRONT, -HALF - WALL, HALF + WALL, floor - 0.1f, ceiling + 0.1f, wallFace, front)
        // The side walls: a low sill, a band over the windows, frames between them.
        for (side in floatArrayOf(1f, -1f)) {
            val (x0, x1) = min(side * HALF, side * (HALF + WALL)) to max(side * HALF, side * (HALF + WALL))
            parts += Block.between(Kind.WALL, x0, x1, floor - 0.1f, SILL, rear, front)
            parts += Block.between(Kind.WALL, x0, x1, LINTEL, ceiling + 0.1f, rear, front)
            var z = -BEHIND
            while (z <= wallFace + 0.01f) {
                parts += Block.between(Kind.FRAME, x0, x1, SILL, LINTEL, max(rear, z - 0.08f), min(front, z + 0.08f))
                z += 1.1f
            }
            // A handrail along each wall at hand height, and another up near the ceiling.
            val hx = side * (HALF - 0.08f)
            parts += Block.between(Kind.HANDRAIL, hx - 0.025f, hx + 0.025f, 1.0f, 1.05f, -BEHIND + 0.2f, wallFace - 0.3f)
            parts += Block.between(Kind.HANDRAIL, hx - 0.025f, hx + 0.025f, LINTEL + 0.12f, LINTEL + 0.17f, -BEHIND + 0.2f, wallFace - 0.3f)
            // Status lights along the ceiling's edges, and a cable run under each.
            parts += Block.between(Kind.STATUS, side * (HALF - 0.05f) - 0.02f, side * (HALF - 0.05f) + 0.02f, ceiling - 0.12f, ceiling - 0.08f, -BEHIND + 0.3f, wallFace - 0.4f)
            parts += Block.between(Kind.CABLE, side * (HALF - 0.2f) - 0.04f, side * (HALF - 0.2f) + 0.04f, ceiling - 0.2f, ceiling - 0.14f, -BEHIND + 0.1f, wallFace - 0.2f)
        }
        // The ceiling, round a skylight over you, ribs across the skylight.
        parts += Block.between(Kind.CEILING, -HALF - WALL, HALF + WALL, ceiling, ceiling + 0.1f, rear, -1.6f)
        parts += Block.between(Kind.CEILING, -HALF - WALL, HALF + WALL, ceiling, ceiling + 0.1f, 0.8f, front)
        for (side in floatArrayOf(1f, -1f))
            parts += Block.between(Kind.CEILING, min(side * 1.1f, side * (HALF + WALL)), max(side * 1.1f, side * (HALF + WALL)), ceiling, ceiling + 0.1f, -1.6f, 0.8f)
        for (z in floatArrayOf(-1.0f, -0.4f, 0.2f)) parts += Block.between(Kind.FRAME, -1.1f, 1.1f, ceiling, ceiling + 0.1f, z - 0.04f, z + 0.04f)

        // Behind you: lockers either side of the hatch, a photo stuck by it, lights blinking on a panel.
        for (side in floatArrayOf(1f, -1f)) for (k in 0 until 2) {
            val x0 = side * (1.0f + k * 0.85f); val x1 = side * (1.75f + k * 0.85f)
            parts += Block.between(Kind.LOCKER, min(x0, x1), max(x0, x1), 0.3f, 2.1f, -BEHIND, -BEHIND + 0.35f)
        }
        parts += Block.between(Kind.HATCH, -0.6f, 0.6f, 0.4f, 2.0f, -BEHIND, -BEHIND + 0.06f)
        parts += Block.between(Kind.PHOTO, 0.68f, 0.92f, 1.5f, 1.66f, -BEHIND + 0.06f, -BEHIND + 0.07f)
        for (k in 0 until 5) {
            val x = -0.45f + k * 0.22f
            parts += Block.between(Kind.LED, x - 0.03f, x + 0.03f, 2.12f, 2.16f, -BEHIND + 0.06f, -BEHIND + 0.08f)
        }
        // Your seat: a padded back behind you, below your eyes.
        parts += Block.between(Kind.SEAT, -0.5f, 0.5f, 0f, 0.12f, -0.55f, 0.05f)
        parts += Block.between(Kind.SEAT, -0.5f, 0.5f, 0.12f, min(0.95f, eyeY - 0.2f), -0.62f, -0.5f)
        // A laptop on its arm at your right; a grow box of greens on your left wall behind you.
        parts += Block.between(Kind.ARM, -1.05f, -1.0f, 0f, 0.85f, -0.05f, 0.0f)
        parts += Block.between(Kind.LAPTOP, -1.1f, -0.75f, 0.85f, 0.87f, -0.15f, 0.1f)
        parts += Block.between(Kind.LAPTOP, -1.1f, -0.75f, 0.87f, 1.1f, 0.08f, 0.1f)
        parts += Block.between(Kind.GROW, HALF - 0.5f, HALF - 0.05f, 0.9f, 1.55f, -2.0f, -1.2f)
        parts += Block.between(Kind.GROW_LIGHT, HALF - 0.48f, HALF - 0.07f, 1.5f, 1.53f, -1.98f, -1.22f)
        for (z in floatArrayOf(-1.85f, -1.6f, -1.35f))
            parts += Block.between(Kind.LEAF, HALF - 0.42f, HALF - 0.12f, 0.95f, 1.3f, z - 0.1f, z + 0.1f)
        // Things drifting free beside you, above your head.
        parts += Block.between(Kind.NOTEBOOK, 0.7f, 0.85f, 1.62f, 1.64f, -0.6f, -0.4f)
        parts += Block.between(Kind.PEN, -0.82f, -0.68f, 1.75f, 1.762f, -0.9f, -0.888f)
        parts += Block.between(Kind.POUCH, 1.15f, 1.23f, 1.45f, 1.57f, 0.05f, 0.09f)
        return parts
    }

    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.FLOOR, Kind.WALL, Kind.CEILING -> Triple(0.66f, 0.67f, 0.69f)
        Kind.PLATFORM, Kind.SEAT -> Triple(0.15f, 0.18f, 0.24f)
        Kind.FRAME -> Triple(0.16f, 0.16f, 0.18f)
        Kind.FRONT -> Triple(0.04f, 0.04f, 0.05f)
        Kind.HANDRAIL -> Triple(0.62f, 0.55f, 0.18f)
        Kind.STATUS -> Triple(0.25f, 0.85f, 1.0f)
        Kind.LED -> Triple(0.2f, 1.0f, 0.4f)
        Kind.ARM, Kind.CABLE -> Triple(0.12f, 0.12f, 0.13f)
        Kind.LAPTOP -> Triple(0.55f, 0.72f, 0.92f)
        Kind.GROW -> Triple(0.55f, 0.56f, 0.58f)
        Kind.GROW_LIGHT -> Triple(0.78f, 0.3f, 0.95f)
        Kind.LEAF -> Triple(0.10f, 0.36f, 0.12f)
        Kind.LOCKER -> Triple(0.60f, 0.61f, 0.63f)
        Kind.HATCH -> Triple(0.30f, 0.30f, 0.32f)
        Kind.PHOTO -> Triple(0.9f, 0.9f, 0.9f)
        Kind.NOTEBOOK -> Triple(0.6f, 0.15f, 0.1f)
        Kind.PEN -> Triple(0.1f, 0.1f, 0.12f)
        Kind.POUCH -> Triple(0.75f, 0.78f, 0.8f)
    }

    fun spill(kind: Kind): Float = when (kind) {
        Kind.STATUS, Kind.LED, Kind.LAPTOP, Kind.GROW_LIGHT -> 0f
        Kind.WALL, Kind.LOCKER, Kind.HATCH, Kind.SEAT -> 0.55f
        Kind.FRONT -> 0.05f
        else -> 0.35f
    }

    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> = when (kind) {
        Kind.LED, Kind.LAPTOP, Kind.GROW_LIGHT -> baseColour(kind)
        // The ceiling's light strips dim for the film, to a glow.
        Kind.STATUS -> (0.35f + 0.65f * level).let { k -> baseColour(kind).let { (r, g, b) -> Triple(r * k, g * k, b * k) } }
        else -> houseLit(baseColour(kind), spill(kind), level, tint)
    }

    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.FLOOR -> Surface(R.drawable.lumiere_tex_grating, 1.0f, 1.0f)
        Kind.WALL, Kind.CEILING, Kind.LOCKER, Kind.GROW -> Surface(R.drawable.lumiere_tex_hull, 1.2f, 1.2f)
        Kind.PLATFORM, Kind.SEAT -> Surface(R.drawable.lumiere_tex_fabric, 0.4f, 0.4f)
        Kind.PHOTO -> Surface(R.drawable.lumiere_tex_art_landscape, 0f, 0f)
        else -> null
    }

    /** What moves: the back panel's lights blink each on its own beat, and the things floating free drift. */
    fun moves(kind: Kind, i: Int, t: Float): Life.Sway? = when (kind) {
        Kind.LED -> Life.blink(t, 1.3f + (i % 4) * 0.45f, 0.5f, i * 0.37f)
        Kind.NOTEBOOK, Kind.PEN, Kind.POUCH -> Life.drift(i, t)
        else -> null
    }
}
