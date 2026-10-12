package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.eyeAspect
import app.lumiere.android.player.Theater
import kotlin.math.tan

/**
 * The Theater's screen as numbers. Five sizes, each a share of your view
 * (55° to 115° across) rather than metres, so a size feels the same in any
 * place. The cinema's and the cabin's screens are walls of a set width, and
 * a size is how near you sit; elsewhere the screen stands at the place's
 * distance and grows: your room's a big TV, the lakeside's an outdoor
 * screen floating over the water. The screen takes the film's own shape
 * (2.39:1 is wide and low, 16:9 taller), and in the cinema you sit high in
 * a raked hall, so even the largest screen's middle is near your eye line.
 * Pure, so it's tested without a headset.
 */
object TheaterGeometry {
    /** How much of your view each size fills, across: from a big screen to an IMAX wall that wraps your view. */
    val SIZE_DEGREES = floatArrayOf(55f, 70f, 85f, 100f, 115f)
    /** Where everyone starts: 85°, a screen that fills your view, as Bigscreen's do. */
    const val DEFAULT_SIZE = 2

    /** The cinema's screen: its hall's (CinemaHall), 20 m across; a size is which row you sit in. */
    const val CINEMA_SCREEN_WIDTH_M = CinemaHall.SCREEN_W
    /** The cabin's screen: a home cinema's wall screen, 5.5 m across; a size is how near the sofa is (5.3 m to 1.75 m). */
    const val CABIN_SCREEN_WIDTH_M = 5.5f
    /** The space station's screen, on its front bulkhead: a size is how near you float to it. */
    const val STATION_SCREEN_WIDTH_M = 4.0f

    /**
     * How far the screen stands, by place and size: in the cinema and the
     * cabin the screen keeps its size and you take a nearer or further seat;
     * elsewhere it stands at the place's distance and grows.
     */
    fun distance(place: Stage.Place, degrees: Float): Float = when (place) {
        Stage.Place.ROOM -> 3.0f
        Stage.Place.CINEMA -> CINEMA_SCREEN_WIDTH_M / (2 * tan(Math.toRadians(degrees / 2.0)).toFloat())   // near enough; spec has the hall's rows
        Stage.Place.CABIN -> CABIN_SCREEN_WIDTH_M / (2 * tan(Math.toRadians(degrees / 2.0)).toFloat())
        Stage.Place.LAKE -> 14f
        Stage.Place.CLOUDS -> 16f
        Stage.Place.MOON -> 18f
        Stage.Place.STATION -> STATION_SCREEN_WIDTH_M / (2 * tan(Math.toRadians(degrees / 2.0)).toFloat())
        Stage.Place.VOID -> 10f
        Stage.Place.SPACE -> 12f
    }

    /**
     * How far above your eyes the screen's middle sits, by place: in your
     * room a touch below, as a TV; at the lakeside well up, over the water
     * and clear of the pontoon you sit on.
     */
    fun aboveEyes(place: Stage.Place): Float = when (place) {
        Stage.Place.ROOM -> -0.05f
        Stage.Place.CINEMA -> CinemaHall.aboveEyes(DEFAULT_SIZE, CinemaHall.SEAT_EYE)
        Stage.Place.CABIN -> 0.2f
        Stage.Place.LAKE -> 0.9f
        Stage.Place.CLOUDS -> 0.9f
        Stage.Place.MOON -> 1.2f
        Stage.Place.STATION -> 0.3f
        Stage.Place.VOID -> 0.1f
        Stage.Place.SPACE -> 0.2f
    }

    /** Whether the screen is part of the place (the cinema's wall, the cabin's), so it stays put; elsewhere it's yours to carry. */
    fun fixedScreen(place: Stage.Place): Boolean = place == Stage.Place.CINEMA || place == Stage.Place.CABIN || place == Stage.Place.STATION

    /**
     * How steeply you look down to the screen's foot, in metres down for each
     * metre ahead: the line that anything on the floor before you must stay
     * under. A curved screen's ends come nearer than its middle, so its line
     * is steeper. 0 for a screen whose foot is above your eyes, and for spheres.
     */
    fun footSlope(spec: Spec): Float {
        if (spec.projection != Projection.FLAT || spec.distanceM <= 0f) return 0f
        val nearest = if (spec.radiusM == null) spec.distanceM
            else spec.distanceM * kotlin.math.cos((spec.widthM / 2 / spec.distanceM).coerceAtMost(1.4f))
        return ((spec.heightM / 2 - spec.aboveEyesM) / nearest).coerceAtLeast(0f)
    }

    /**
     * Everything the screen's panel is made from. [radiusM] null is flat;
     * otherwise it curves on that radius, centred on you.
     */
    data class Spec(
        val projection: Projection, val eyes: StereoLayout,
        val widthM: Float, val heightM: Float, val radiusM: Float?,
        val distanceM: Float, val aboveEyesM: Float,
        val pixelWidth: Int, val pixelHeight: Int,
    )

    /**
     * The screen for [request], [place], [size] and [curved]; [scopeFill]: a
     * wide film as tall as a 16:9 one, so wider (Stage.scopeFill). In the
     * cinema the screen is the hall's own, flat in its frame, and [size] is
     * your row: its middle is as far above your eyes ([eyeY] over the floor)
     * as the hall has it.
     */
    fun spec(request: Theater.Request, place: Stage.Place, size: Int, curved: Boolean, scopeFill: Boolean = false,
             eyeY: Float = CinemaHall.SEAT_EYE): Spec {
        val (pw, ph) = pictureSize(request)
        if (request.projection != Projection.FLAT)
            return Spec(request.projection, request.eyes, 0f, 0f, null, SPHERE_RADIUS_M, 0f, pw, ph)
        if (place == Stage.Place.CINEMA) {
            val (w, h) = CinemaHall.picture(aspectOf(request))
            return Spec(request.projection, request.eyes, w, h, null, CinemaHall.distance(size), CinemaHall.aboveEyes(size, eyeY), pw, ph)
        }
        val degrees = SIZE_DEGREES[size.coerceIn(0, SIZE_DEGREES.lastIndex)]
        val d = distance(place, degrees)
        val radians = Math.toRadians(degrees.toDouble()).toFloat()
        // Curved, the arc spans the angle; flat, the chord does.
        var width = if (curved) d * radians else 2 * d * tan(radians / 2)
        val aspect = eyeAspect(request.eyes, request.width, request.height).coerceIn(1.2f, 2.8f)
        // A scope cinema's way: the height a 16:9 film would have, the width from that — but a curve never wraps past 130°, where its ends would come round beside you.
        if (scopeFill && aspect > WIDE) {
            width = width / WIDE * aspect
            if (curved) width = width.coerceAtMost(d * Math.toRadians(MAX_ARC_DEGREES.toDouble()).toFloat())
        }
        return Spec(request.projection, request.eyes, width, width / aspect, if (curved) d else null,
            d, aboveEyes(place), pw, ph)
    }

    /** The film's shape across, kept within what a screen can sensibly be. */
    fun aspectOf(request: Theater.Request): Float = eyeAspect(request.eyes, request.width, request.height).coerceIn(1.2f, 2.8f)

    /** The screen on your wall (WallMount): flat, [widthM] across, [distanceM] from where you stood to mount it. */
    fun mounted(request: Theater.Request, widthM: Float, distanceM: Float): Spec {
        val (pw, ph) = pictureSize(request)
        return Spec(request.projection, request.eyes, widthM, widthM / aspectOf(request), null, distanceM, 0f, pw, ph)
    }

    /** A 16:9 picture's shape, which a wide film's screen keeps the height of when filling (scopeFill). */
    const val WIDE = 16f / 9f
    private const val MAX_ARC_DEGREES = 130f

    /** A sphere this far out: far enough that its curve and your small movements don't show. */
    const val SPHERE_RADIUS_M = 50f

    /** The film's own picture size, never past what the headset decodes. */
    fun pictureSize(request: Theater.Request): Pair<Int, Int> {
        if (request.width > 0 && request.height > 0)
            return request.width.coerceAtMost(MAX_SIDE) to request.height.coerceAtMost(MAX_SIDE)
        return if (request.projection == Projection.SPHERE && request.eyes == StereoLayout.TOP_BOTTOM) 3840 to 3840 else 3840 to 2160
    }

    private const val MAX_SIDE = 8192

    /** How wide [widthM] at [distanceM] looks, in degrees (flat). */
    fun angleDegrees(widthM: Float, distanceM: Float): Float =
        Math.toDegrees(2 * kotlin.math.atan((widthM / 2 / distanceM).toDouble())).toFloat()

    /**
     * The captions' panel on a screen: a band over its foot, just in front
     * of it, laid out so a line of the middle size is [CAPTION_LINE_DEGREES]
     * of your view whatever the screen's size or distance — a wall TV's
     * captions as readable as the cinema's. Room for two speakers and the
     * second language under them, within the screen's lower half. In front
     * of a curved screen's ends, which come nearer than its middle. Width,
     * height, how far up from the screen's middle its own middle sits, how
     * far in front, and its width in dp.
     */
    fun captions(spec: Spec): FloatArray {
        if (spec.projection != Projection.FLAT) return nearCaptions(spec)
        val r = spec.radiusM
        val w = (spec.widthM * 0.8f).let { if (r != null) it.coerceAtMost(0.7f * r) else it }
        val sag = if (r == null) 0f else r - kotlin.math.sqrt((r * r - w * w / 4).coerceAtLeast(0f))
        val ahead = 0.04f + sag
        val perM = dpPerMetre((spec.distanceM - ahead).coerceAtLeast(0.5f))
        val h = (CAPTION_ROOM_DP / perM).coerceAtMost(spec.heightM * 0.45f)
        return floatArrayOf(w, h, -spec.heightM / 2 + h / 2 + spec.heightM * 0.03f, ahead, w * perM)
    }

    /**
     * Captions before you, low in your view, for 180° and 360° and wherever
     * you'd rather have them there: [SPHERE_CAPTIONS_DISTANCE_M] away, or
     * nearer than a screen that's closer (the cabin's, the station's), so
     * it never hides them. Width, height, how far below your eyes, how far
     * ahead, and its width in dp.
     */
    fun nearCaptions(spec: Spec?): FloatArray {
        val nearest = when {
            spec == null || spec.projection != Projection.FLAT -> Float.MAX_VALUE
            spec.radiusM != null -> spec.distanceM * kotlin.math.cos((spec.widthM / 2 / spec.distanceM).coerceAtMost(1.4f))
            else -> spec.distanceM
        }
        val d = minOf(SPHERE_CAPTIONS_DISTANCE_M, nearest * 0.75f).coerceAtLeast(0.6f)
        val perM = dpPerMetre(d)
        val w = d * NEAR_CAPTIONS_W / SPHERE_CAPTIONS_DISTANCE_M
        return floatArrayOf(w, CAPTION_ROOM_DP / perM, d * 0.22f, d, w * perM)
    }

    /** dp to the metre for a panel [distance] away, so a middle-size line is [CAPTION_LINE_DEGREES] tall. */
    private fun dpPerMetre(distance: Float): Float =
        CAPTION_LINE_DP / (distance * tan(Math.toRadians(CAPTION_LINE_DEGREES.toDouble())).toFloat())

    /** A caption line of the middle size, in degrees of your view; its height in the captions' dp (TheaterCaptions). */
    const val CAPTION_LINE_DEGREES = 1.3f
    const val CAPTION_LINE_DP = 46f
    /** Room on the captions' panel: two speakers' lines at the largest size and the second language under them. */
    const val CAPTION_ROOM_DP = 400f

    /** For 180° and 360°, and wherever you want them before you: captions this far in front of you at most, this wide there. */
    const val SPHERE_CAPTIONS_DISTANCE_M = 2.5f
    const val NEAR_CAPTIONS_W = 2.0f
}
