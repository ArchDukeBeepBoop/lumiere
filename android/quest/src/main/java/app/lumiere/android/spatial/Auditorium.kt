package app.lumiere.android.spatial

import kotlin.math.max
import kotlin.math.min

/**
 * The cinema round the screen: a stadium-seated hall where you sit high in
 * a raked row, so a screen many metres across stands with its middle near
 * your eye line, as from the best seats. Rows of real seats — velvet
 * cushions and backs, shared arms with cup holders, end standards at the
 * aisles — step down toward a stage on carpeted risers with lit nosings;
 * framed acoustic panels, surround speakers and warm sconces line the
 * walls; beams cross a ceiling of tiny stars; a gilt proscenium frames the
 * screen, with velvet drapes in folds either side and a pleated valance
 * over it, and front curtains that gather to the sides as the film begins
 * (FrontCurtain). The projection booth's windows glow behind you.
 *
 * Laid out in your seat's own frame: you at the origin on the real floor
 * (y = 0, your row's platform), facing +Z, your left +X; the screen's
 * middle at (0, [screenMiddleY], [distance]). [build] gives each part's
 * bounds — what the tests check sightlines against — and [shape] models it
 * inside them. Pure, so it's tested without a headset; Scenery makes it.
 */
object Auditorium {
    enum class Kind {
        FLOOR, STEP, SEAT, WALL, PANEL, CEILING, STAGE, MASK, SCREEN_WALL, AISLE_LIGHT, EXIT_SIGN, BALCONY,
        CURTAIN, VALANCE, SCONCE, BOOTH, BEAM, STARS, PROSCENIUM, SPEAKER,
        /** The front curtain's strips, open in the layout; FrontCurtain draws them across. */
        TABS,
        // Made only within the parts above: a step's nosing, a seat's frame and cup holders,
        // timber trim round panels and lamps, a speaker's grille.
        NOSING, SEAT_FRAME, CUP, TRIM, GRILLE,
    }

    /** One part's bounds, as Block: the name the hall's code and tests know it by. */
    private fun Part(kind: Kind, x: Float, y: Float, z: Float, w: Float, h: Float, d: Float) = Block(kind, x, y, z, w, h, d)

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
    /** A row of seats, from its floor: the backs' tops, and how far behind and ahead of the row's line they reach. */
    const val SEATS_TALL = 0.95f
    private const val SEATS_BEHIND = 0.45f
    private const val SEATS_AHEAD = 0.28f
    private const val BEHIND = 2.6f
    /** The front curtain: strips a side, how far they gather beyond the screen's edge, and how far they overlap closed. */
    const val TAB_STRIPS = 7
    const val TAB_GATHER = 1.2f
    const val TAB_OVERLAP = 0.15f
    /** Open, how far the innermost strip's edge stands clear of the screen's. */
    const val TAB_CLEAR = 0.05f

    /**
     * The hall for a screen [screenWidth] × [screenHeight] whose middle is at
     * height [screenMiddleY], [distance] ahead, seen from eyes at [eyeY].
     */
    fun build(screenWidth: Float, screenHeight: Float, screenMiddleY: Float, distance: Float, eyeY: Float = 1.2f): List<Block<Kind>> {
        val parts = mutableListOf<Block<Kind>>()
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
        seats(parts, CLEAR_BESIDE_YOU, seatHalf, 0f, 0f)
        seats(parts, -seatHalf, -CLEAR_BESIDE_YOU, 0f, 0f)
        // A row behind you, a step up, and the back wall.
        parts += Part(Kind.STEP, 0f, rake / 2, -1.1f - 0.3f, hallWidth, rake, 1.2f)
        seats(parts, -seatHalf, seatHalf, rake, -1.1f)
        parts += Part(Kind.WALL, 0f, (ceiling + 0f) / 2, -BEHIND, hallWidth, ceiling + 0.2f, 0.2f)

        // The rows ahead, each a step lower: a riser, then its seats; an amber light at each aisle step.
        for (k in 1..rows) {
            val z = k * ROW_PITCH
            val floor = -k * rake
            parts += Part(Kind.STEP, 0f, floor - 0.05f, z, hallWidth, 0.1f, ROW_PITCH)
            parts += Part(Kind.STEP, 0f, floor + rake / 2, z - ROW_PITCH / 2, hallWidth, rake, 0.04f)
            seats(parts, -seatHalf, seatHalf, floor, z)
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

        // Walls from the floor to the ceiling, with framed acoustic panels every 2.5 m; the ceiling over all.
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
        // Beams across the ceiling every three metres, and a field of tiny stars between them.
        z = -BEHIND + 1.5f
        while (z < distance - 0.5f) {
            parts += Part(Kind.BEAM, 0f, ceiling - 0.17f, z, hallWidth, 0.34f, 0.3f)
            z += 3f
        }
        parts += Part(Kind.STARS, 0f, ceiling - 0.005f, hallMiddleZ, hallWidth - 0.4f, 0.01f, hallLength - 0.6f)

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

        // Velvet drapes in folds either side of the screen and a valance over it: beyond its edges
        // and above its top, so they frame the picture and never cross it.
        for (side in floatArrayOf(1f, -1f)) for (k in 0 until 2) {
            val x = side * (screenWidth / 2 + 0.15f + 0.35f + k * 0.7f)
            val dz = distance - 0.32f - 0.1f * k
            parts += Part(Kind.CURTAIN, x, (frontFloor + ceiling - 0.4f) / 2, dz, 0.7f, ceiling - 0.4f - frontFloor, 0.12f)
        }
        val valanceBottom = screenTop + 0.25f
        if (ceiling - valanceBottom > 0.3f)
            parts += Part(Kind.VALANCE, 0f, (valanceBottom + ceiling) / 2, distance - 0.3f, screenWidth + 3.3f, ceiling - valanceBottom, 0.12f)
        // The proscenium: gilt pilasters beyond the drapes and a header over the valance.
        val pilasterX = screenWidth / 2 + 1.75f
        if (pilasterX + 0.4f < half) for (side in floatArrayOf(1f, -1f))
            parts += Part(Kind.PROSCENIUM, side * (pilasterX + 0.2f), (frontFloor + ceiling) / 2, distance - 0.45f, 0.4f, ceiling - frontFloor, 0.3f)
        if (ceiling - valanceBottom > 0.6f)
            parts += Part(Kind.PROSCENIUM, 0f, ceiling - 0.2f, distance - 0.45f, min(hallWidth - 0.2f, 2 * pilasterX + 0.8f), 0.4f, 0.3f)
        // The front curtain: strips either side, here gathered open beyond the screen's edge, behind the drapes;
        // each a little nearer you than the one inside it, and the right half nearer than the left, so where
        // they lie over each other one is always in front.
        val tabTop = valanceBottom + 0.05f
        val tabBottom = stageTop
        val stripW = (screenWidth / 2 + TAB_OVERLAP) / TAB_STRIPS
        for (side in floatArrayOf(1f, -1f)) for (k in 0 until TAB_STRIPS) {
            val x = side * (screenWidth / 2 + TAB_CLEAR + stripW / 2 + TAB_GATHER * k / TAB_STRIPS)
            val dz = distance - 0.12f - 0.006f * k - (if (side < 0f) 0.05f else 0f)
            parts += Part(Kind.TABS, x, (tabTop + tabBottom) / 2, dz, stripW, tabTop - tabBottom, 0.06f)
        }
        // Warm sconces down both walls, between every other pair of panels, at a lamp's height over the floor
        // beneath; surround speakers high on the walls between them.
        z = -BEHIND + 2.75f
        var speaker = true
        while (z < distance - 1.5f) {
            val floor = floorAt(z, rake, frontFloor)
            parts += Part(Kind.SCONCE, half - 0.06f, floor + 2.4f, z, 0.12f, 0.3f, 0.18f)
            parts += Part(Kind.SCONCE, -half + 0.06f, floor + 2.4f, z, 0.12f, 0.3f, 0.18f)
            val sz = z + 2.5f
            if (speaker && sz < distance - 1.5f) {
                val sf = floorAt(sz, rake, frontFloor)
                parts += Part(Kind.SPEAKER, half - 0.11f, sf + 3.3f, sz, 0.22f, 0.5f, 0.34f)
                parts += Part(Kind.SPEAKER, -half + 0.11f, sf + 3.3f, sz, 0.22f, 0.5f, 0.34f)
            }
            speaker = !speaker
            z += 5f
        }
        // The projection booth's two windows, high in the back wall behind you.
        for (x in floatArrayOf(-0.6f, 0.6f)) parts += Part(Kind.BOOTH, x, ceiling - 1.0f, -BEHIND + 0.11f, 0.5f, 0.32f, 0.02f)
        return parts
    }

    private fun floorAt(z: Float, rake: Float, frontFloor: Float) = if (z <= 0f) 0f else max(frontFloor, -(z / ROW_PITCH) * rake)

    /** A run of seats from [fromX] to [toX], on a floor at [floor], its row at [z]: one part, its seats modelled within it. */
    private fun seats(parts: MutableList<Block<Kind>>, fromX: Float, toX: Float, floor: Float, z: Float) {
        if (toX - fromX <= 0.5f) return
        parts += Block.between(Kind.SEAT, fromX, toX, floor, floor + SEATS_TALL, z - SEATS_BEHIND, z + SEATS_AHEAD)
    }

    private const val SEAT_PITCH = 0.58f
    private const val BACK_TILT = 12f

    /**
     * How each part is made, inside its bounds: seats as seats, steps with
     * their nosings, panels padded and framed, the drapes and the curtain in
     * folds, lamps on their brackets; the rest as they are.
     */
    fun shape(b: Block<Kind>, m: Modeller<Kind>) {
        val x0 = b.x - b.w / 2; val x1 = b.x + b.w / 2
        when (b.kind) {
            Kind.SEAT -> seatRow(b, m)
            Kind.STEP -> {
                m.box(b, skip = Modeller.DOWN_FACE)
                // A riser's lit nosing along its top edge: a pale strip you'd find in the dark.
                if (b.d < 0.1f) {
                    m.part(Kind.NOSING, b.x)
                    m.box(x0, x1, b.top - 0.025f, b.top, b.back, b.front, skip = Modeller.DOWN_FACE)
                }
            }
            Kind.FLOOR -> m.box(b, skip = Modeller.DOWN_FACE)
            // Walls show only their faces into the hall; the ceiling only its underside.
            Kind.WALL -> m.box(b, skip = Modeller.UP_FACE or Modeller.DOWN_FACE or when {
                b.x > 1f -> Modeller.LEFT_FACE
                b.x < -1f -> Modeller.RIGHT_FACE
                else -> Modeller.BACK_FACE
            })
            Kind.CEILING -> m.box(b, skip = Modeller.UP_FACE)
            Kind.SCREEN_WALL -> m.box(b, skip = Modeller.UP_FACE or Modeller.DOWN_FACE or Modeller.FRONT_FACE)
            Kind.STAGE -> m.chamfered(x0, x1, b.bottom, b.top, b.back, b.front, 0.03f, skip = Modeller.DOWN_FACE)
            Kind.PANEL -> panel(b, m)
            Kind.CURTAIN -> m.pleats(x0, x1, b.bottom, b.top, b.front - 0.01f, b.d - 0.02f, folds = 3)
            Kind.VALANCE -> {
                m.pleats(x0, x1, b.bottom + 0.06f, b.top, b.front - 0.01f, b.d - 0.03f, folds = (b.w / 0.5f).toInt().coerceAtLeast(4), steps = 4)
                // A gilt fringe along its hem.
                m.part(Kind.TRIM, b.x)
                m.box(x0, x1, b.bottom, b.bottom + 0.06f, b.back + 0.02f, b.front - 0.02f)
            }
            Kind.TABS -> m.pleats(x0, x1, b.bottom, b.top, b.front - 0.01f, b.d - 0.02f, folds = 2)
            Kind.SCONCE -> {
                // A bracket on the wall, a glowing shade standing off it.
                val wallSide = if (b.x > 0f) 1f else -1f
                m.part(Kind.TRIM, b.x)
                val bx0 = if (wallSide > 0) x1 - 0.02f else x0
                m.box(bx0, bx0 + 0.02f, b.bottom, b.top, b.back + 0.04f, b.front - 0.04f)
                m.part(Kind.SCONCE, b.x)
                val sx0 = if (wallSide > 0) x0 else x0 + 0.03f
                m.chamfered(sx0, sx0 + b.w - 0.03f, b.bottom + 0.05f, b.top - 0.03f, b.back, b.front, 0.03f)
            }
            Kind.SPEAKER -> {
                // The cabinet, its cloth grille on the face turned into the hall.
                val left = b.x > 0f
                m.chamfered(if (left) x0 + 0.012f else x0, if (left) x1 else x1 - 0.012f, b.bottom, b.top, b.back, b.front, 0.02f)
                m.part(Kind.GRILLE, b.x)
                val gx = if (left) x0 else x1 - 0.012f
                m.box(gx, gx + 0.012f, b.bottom + 0.04f, b.top - 0.04f, b.back + 0.03f, b.front - 0.03f)
            }
            Kind.PROSCENIUM -> {
                m.chamfered(x0, x1, b.bottom, b.top, b.back, b.front, 0.05f)
                // Fluting: two shallow reeds down a pilaster's face, a moulding under the header.
                m.part(Kind.TRIM, b.x)
                if (b.h > b.w * 2) for (k in 0..1) {
                    val rx = x0 + b.w * (0.3f + 0.4f * k)
                    m.chamfered(rx - 0.03f, rx + 0.03f, b.bottom + 0.3f, b.top - 0.3f, b.back, b.back + 0.04f, 0.012f)
                } else m.chamfered(x0 + 0.1f, x1 - 0.1f, b.bottom, b.bottom + 0.06f, b.back, b.back + 0.05f, 0.02f)
            }
            Kind.EXIT_SIGN -> {
                m.chamfered(x0, x1, b.bottom, b.top - 0.03f, b.back, b.front, 0.015f)
                m.part(Kind.SEAT_FRAME, b.x)
                m.box(x0, x1, b.top - 0.03f, b.top, b.back, b.front)
            }
            Kind.BOOTH -> {
                // A lit pane in a timber frame.
                val f = 0.04f
                m.box(x0 + f, x1 - f, b.bottom + f, b.top - f, b.back, b.front)
                m.part(Kind.TRIM, b.x)
                m.box(x0, x1, b.top - f, b.top, b.back, b.front)
                m.box(x0, x1, b.bottom, b.bottom + f, b.back, b.front)
                m.box(x0, x0 + f, b.bottom + f, b.top - f, b.back, b.front)
                m.box(x1 - f, x1, b.bottom + f, b.top - f, b.back, b.front)
            }
            Kind.BALCONY -> {
                m.chamfered(x0, x1, b.bottom, b.top - 0.06f, b.back, b.front, 0.03f)
                m.part(Kind.TRIM, b.x)
                m.chamfered(x0, x1, b.top - 0.06f, b.top, b.back - 0.02f, b.front + 0.02f, 0.025f)
            }
            Kind.STARS -> stars(b, m)
            Kind.BEAM -> m.chamfered(x0, x1, b.bottom, b.top, b.back, b.front, 0.04f, skip = Modeller.UP_FACE)
            else -> m.box(b)
        }
    }

    /**
     * A row of seats within [b]: each a velvet cushion and back (the back
     * leaning back as a cinema seat's does) on a dark pan and shell; arms
     * between them, shared, each with a cup holder; end standards at the
     * aisles. Within [DETAIL_M] of you they're modelled in full; beyond,
     * where a bevel or a cup holder is a pixel, as plain shapes.
     */
    private fun seatRow(b: Block<Kind>, m: Modeller<Kind>) {
        val floor = b.bottom
        val zr = b.front - SEATS_AHEAD
        val x0 = b.x - b.w / 2 + 0.04f; val x1 = b.x + b.w / 2 - 0.04f
        val n = ((x1 - x0) / SEAT_PITCH).toInt().coerceAtLeast(1)
        val pitch = (x1 - x0) / n
        fun near(x: Float) = x * x + zr * zr < DETAIL_M * DETAIL_M
        for (i in 0 until n) {
            val cx = x0 + pitch * (i + 0.5f)
            val half = pitch / 2 - 0.045f
            val full = near(cx)
            m.part(Kind.SEAT, b.x)
            if (full) m.chamfered(cx - half, cx + half, floor + 0.40f, floor + 0.50f, zr - 0.20f, zr + 0.24f, 0.035f, skip = Modeller.DOWN_FACE)
            else m.box(cx - half, cx + half, floor + 0.40f, floor + 0.50f, zr - 0.20f, zr + 0.24f, skip = Modeller.DOWN_FACE)
            m.tilted(BACK_TILT, floor + 0.42f, zr - 0.24f) {
                if (full) m.chamfered(cx - half, cx + half, floor + 0.46f, floor + 0.90f, zr - 0.29f, zr - 0.18f, 0.04f, skip = Modeller.BACK_FACE)
                else m.box(cx - half, cx + half, floor + 0.46f, floor + 0.90f, zr - 0.29f, zr - 0.18f, skip = Modeller.BACK_FACE or Modeller.DOWN_FACE)
            }
            m.part(Kind.SEAT_FRAME, b.x)
            if (full) m.box(cx - half + 0.02f, cx + half - 0.02f, floor + 0.20f, floor + 0.40f, zr - 0.16f, zr + 0.18f, skip = Modeller.DOWN_FACE)
            m.tilted(BACK_TILT, floor + 0.42f, zr - 0.24f) {
                m.box(cx - half - 0.01f, cx + half + 0.01f, floor + 0.42f, floor + 0.93f, zr - 0.33f, zr - 0.285f,
                    skip = if (full) 0 else Modeller.DOWN_FACE or Modeller.FRONT_FACE)
            }
        }
        for (k in 0..n) {
            val ax = x0 + pitch * k
            val end = k == 0 || k == n
            val full = near(ax)
            m.part(Kind.SEAT_FRAME, b.x)
            when {
                end && full -> m.chamfered(ax - 0.03f, ax + 0.03f, floor, floor + 0.68f, zr - 0.32f, zr + 0.22f, 0.02f)
                end -> m.box(ax - 0.03f, ax + 0.03f, floor, floor + 0.68f, zr - 0.32f, zr + 0.22f, skip = Modeller.DOWN_FACE)
                full -> m.box(ax - 0.02f, ax + 0.02f, floor, floor + 0.58f, zr - 0.20f, zr + 0.08f, skip = Modeller.DOWN_FACE)
            }
            if (full) m.chamfered(ax - 0.04f, ax + 0.04f, floor + 0.58f, floor + 0.64f, zr - 0.30f, zr + 0.22f, 0.015f)
            else if (!end) m.box(ax - 0.04f, ax + 0.04f, floor + 0.58f, floor + 0.64f, zr - 0.30f, zr + 0.22f, skip = Modeller.DOWN_FACE)
            if (!end && full) {
                m.part(Kind.CUP, b.x)
                m.cylinder(ax, zr + 0.16f, 0.036f, floor + 0.60f, floor + 0.645f, segments = 10)
            }
        }
    }

    /** How near you seats are modelled in full. */
    private const val DETAIL_M = 5f

    /** An acoustic panel within [b] on a side wall: padded cloth in a timber frame, facing into the hall. */
    private fun panel(b: Block<Kind>, m: Modeller<Kind>) {
        val x0 = b.x - b.w / 2; val x1 = b.x + b.w / 2
        val frame = 0.06f
        m.chamfered(x0, x1, b.bottom + frame, b.top - frame, b.back + frame, b.front - frame, 0.03f)
        m.part(Kind.TRIM, b.x)
        m.chamfered(x0, x1, b.top - frame, b.top, b.back, b.front, 0.015f)
        m.chamfered(x0, x1, b.bottom, b.bottom + frame, b.back, b.front, 0.015f)
        m.chamfered(x0, x1, b.bottom + frame, b.top - frame, b.back, b.back + frame, 0.015f)
        m.chamfered(x0, x1, b.bottom + frame, b.top - frame, b.front - frame, b.front, 0.015f)
    }

    /** Tiny lights scattered over the ceiling within [b], a few brighter, the same for the same hall. */
    private fun stars(b: Block<Kind>, m: Modeller<Kind>) {
        var seed = 0x2545F491L xor (b.w * 1000f).toLong() xor ((b.d * 1000f).toLong() shl 16)
        fun next(): Float { seed = (seed * 6364136223846793005L + 1442695040888963407L); return ((seed ushr 33) and 0xFFFFFF).toFloat() / 0xFFFFFF }
        val count = (b.w * b.d / 2.2f).toInt().coerceIn(40, 260)
        val y = b.bottom
        repeat(count) {
            val x = b.x - b.w / 2 + next() * b.w
            val z = b.back + next() * b.d
            val s = 0.008f + 0.014f * next() * next()
            m.face(floatArrayOf(x - s, y, z - s, x + s, y, z - s, x + s, y, z + s, x - s, y, z + s), floatArrayOf(0f, -1f, 0f))
        }
    }

    /** Each kind's colour under full house lights, 0..1. */
    fun baseColour(kind: Kind): Triple<Float, Float, Float> = when (kind) {
        Kind.FLOOR -> Triple(0.13f, 0.10f, 0.20f)
        Kind.STEP -> Triple(0.14f, 0.11f, 0.21f)
        Kind.NOSING -> Triple(0.55f, 0.47f, 0.30f)
        Kind.SEAT -> Triple(0.50f, 0.07f, 0.10f)
        Kind.SEAT_FRAME -> Triple(0.08f, 0.075f, 0.08f)
        Kind.CUP -> Triple(0.03f, 0.03f, 0.035f)
        Kind.WALL -> Triple(0.20f, 0.15f, 0.14f)
        Kind.PANEL -> Triple(0.30f, 0.22f, 0.20f)
        Kind.TRIM -> Triple(0.42f, 0.27f, 0.14f)
        Kind.CEILING -> Triple(0.05f, 0.05f, 0.06f)
        Kind.BEAM -> Triple(0.09f, 0.08f, 0.09f)
        Kind.STARS -> Triple(0.95f, 0.90f, 0.78f)
        Kind.STAGE -> Triple(0.24f, 0.15f, 0.09f)
        Kind.MASK -> Triple(0.012f, 0.012f, 0.014f)
        Kind.SCREEN_WALL -> Triple(0.02f, 0.02f, 0.025f)
        Kind.BALCONY -> Triple(0.22f, 0.16f, 0.15f)
        Kind.AISLE_LIGHT -> Triple(1.0f, 0.62f, 0.22f)
        Kind.EXIT_SIGN -> Triple(0.2f, 0.95f, 0.45f)
        Kind.CURTAIN, Kind.VALANCE, Kind.TABS -> Triple(0.46f, 0.05f, 0.08f)
        Kind.SCONCE -> Triple(1.0f, 0.72f, 0.42f)
        Kind.BOOTH -> Triple(0.85f, 0.82f, 0.72f)
        Kind.PROSCENIUM -> Triple(0.52f, 0.40f, 0.18f)
        Kind.SPEAKER -> Triple(0.06f, 0.06f, 0.065f)
        Kind.GRILLE -> Triple(0.12f, 0.12f, 0.13f)
    }

    /** Whether a kind is shaded by the way its faces look: not lights, nor what's all but black. */
    fun shaded(kind: Kind): Boolean = !glows(kind) && kind != Kind.MASK && kind != Kind.SCREEN_WALL && kind != Kind.CUP && kind != Kind.GRILLE

    /** Whether a kind takes the light of its own side of the picture: what's on the side walls. */
    fun sided(kind: Kind): Boolean = kind == Kind.WALL || kind == Kind.PANEL || kind == Kind.TRIM || kind == Kind.CURTAIN ||
        kind == Kind.PROSCENIUM || kind == Kind.SPEAKER

    /** Lights, signs and the stars: they shine at their own colour, not shaded by which way they face. */
    fun glows(kind: Kind): Boolean = kind == Kind.AISLE_LIGHT || kind == Kind.EXIT_SIGN || kind == Kind.SCONCE ||
        kind == Kind.BOOTH || kind == Kind.STARS

    /** How much of the film's light a kind catches (what faces the screen most catches most); lights shine on their own. */
    fun spill(kind: Kind): Float = when (kind) {
        Kind.AISLE_LIGHT, Kind.EXIT_SIGN, Kind.MASK, Kind.SCONCE, Kind.BOOTH, Kind.STARS -> 0f
        Kind.CURTAIN, Kind.VALANCE, Kind.TABS, Kind.PROSCENIUM -> 0.5f
        Kind.SEAT, Kind.STAGE, Kind.BALCONY, Kind.NOSING -> 0.55f
        Kind.CEILING, Kind.BEAM -> 0.25f
        else -> 0.4f
    }

    /**
     * A part's colour with the house lights at [level] (1 up, about 0.12
     * during a film) and the film's [tint] spilling as they go down. The
     * hall stays visible in the dark; the signs never dim; the sconces go
     * almost out; the stars stay, softly.
     */
    fun colour(kind: Kind, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> {
        val (r, g, b) = baseColour(kind)
        return when (kind) {
            Kind.AISLE_LIGHT, Kind.EXIT_SIGN, Kind.BOOTH -> Triple(r, g, b)
            Kind.SCONCE -> (0.1f + 0.9f * level).let { k -> Triple(r * k, g * k, b * k) }
            Kind.STARS -> (0.45f + 0.35f * level).let { k -> Triple(r * k, g * k, b * k) }
            else -> houseLit(Triple(r, g, b), spill(kind), level, tint)
        }
    }

    /** What each kind is made of: patterned carpet, velvet, cloth walls and ribbed panels, timber. */
    fun surface(kind: Kind): Surface? = when (kind) {
        Kind.FLOOR, Kind.STEP -> Surface(R.drawable.lumiere_tex_carpet, 2.4f, 2.4f)
        Kind.SEAT, Kind.CURTAIN, Kind.VALANCE, Kind.TABS -> Surface(R.drawable.lumiere_tex_velvet, 0.5f, 0.5f)
        Kind.WALL, Kind.BALCONY -> Surface(R.drawable.lumiere_tex_fabric, 1.2f, 1.2f)
        Kind.PANEL -> Surface(R.drawable.lumiere_tex_panel, 0.4f, 0f)
        Kind.STAGE, Kind.TRIM -> Surface(R.drawable.lumiere_tex_wood, 1.2f, 1.2f)
        Kind.GRILLE -> Surface(R.drawable.lumiere_tex_fabric, 0.3f, 0.3f)
        else -> null
    }

    /** What moves: the front curtain's strips, drawn across as FrontCurtain says. */
    fun moves(b: Block<Kind>, t: Float): Life.Sway? = if (b.kind == Kind.TABS) FrontCurtain.sway(b) else null
}
