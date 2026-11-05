package app.lumiere.android.spatial

import kotlin.math.tan

/**
 * The Theater's screen as numbers, in your room. A size is a share of your
 * view across (55° to 115°) rather than metres, so it feels the same however
 * far the screen stands; it stands [ROOM_DISTANCE_M] away, a touch below your
 * eyes as a TV does, in the film's own shape — 2.39:1 wide and low, 16:9
 * taller — and never taller than your view comfortably takes. Its captions
 * sit just under its foot, at a size read at that distance. Pure, so it's
 * tested without a headset. From the spatial app (docs/quest/HANDOVER.md).
 */
object TheaterGeometry {
    /**
     * How much of your view each size fills, across: from a TV to a cinema's.
     * 85° filled the view and was too big to watch in a room; everyone starts
     * at 45°, a big TV (ScreenPlace keeps your choice).
     */
    val SIZE_DEGREES = floatArrayOf(35f, 45f, 55f, 70f, 85f)
    const val DEFAULT_SIZE = 1

    const val ROOM_DISTANCE_M = 3.0f
    const val ROOM_ABOVE_EYES_M = -0.05f
    /** No taller than this share of your view up and down, however narrow the picture. */
    const val MAX_TALL_DEGREES = 62f
    /** The most pixels the screen is laid out at: 4K, whatever the film. */
    const val MAX_PIXELS_WIDE = 3840
    /** 180° and 360° are drawn on a sphere this far out: far enough that its curve and your small movements don't show. */
    const val SPHERE_RADIUS_M = 50f

    /** The screen for a [videoWidth] × [videoHeight] picture at [size]. */
    /** Where you sit: nearer or further back; the screen keeps its size, so it fills more or less of your view. */
    val SEAT_NAMES = listOf("Near", "Middle", "Far")
    private val SEAT_SCALE = floatArrayOf(0.75f, 1f, 1.4f)

    fun seated(spec: Spec, seat: Int): Spec {
        val f = SEAT_SCALE[seat.coerceIn(0, SEAT_SCALE.size - 1)]
        return spec.copy(distanceM = spec.distanceM * f, aboveEyesM = spec.aboveEyesM * f)
    }

    data class Spec(
        val widthM: Float, val heightM: Float, val distanceM: Float, val aboveEyesM: Float,
        val pixelWidth: Int, val pixelHeight: Int,
    )

    fun room(videoWidth: Int, videoHeight: Int, size: Int = DEFAULT_SIZE): Spec {
        val aspect = if (videoWidth > 0 && videoHeight > 0) videoWidth.toFloat() / videoHeight else 16f / 9f
        val degrees = SIZE_DEGREES[size.coerceIn(0, SIZE_DEGREES.size - 1)]
        var width = span(degrees, ROOM_DISTANCE_M)
        var height = width / aspect
        val tallest = span(MAX_TALL_DEGREES, ROOM_DISTANCE_M)
        if (height > tallest) { height = tallest; width = height * aspect }
        val px = videoWidth.coerceIn(1, MAX_PIXELS_WIDE).takeIf { videoWidth > 0 } ?: 1920
        return Spec(width, height, ROOM_DISTANCE_M, ROOM_ABOVE_EYES_M, px, (px / aspect).toInt().coerceAtLeast(1))
    }

    /** A screen [widthM] wide at [distance] (on your wall, pinned), in the film's shape. */
    fun sized(widthM: Float, videoWidth: Int, videoHeight: Int, distance: Float): Spec {
        val aspect = if (videoWidth > 0 && videoHeight > 0) videoWidth.toFloat() / videoHeight else 16f / 9f
        val px = videoWidth.coerceIn(1, MAX_PIXELS_WIDE).takeIf { videoWidth > 0 } ?: 1920
        return Spec(widthM, widthM / aspect, distance, 0f, px, (px / aspect).toInt().coerceAtLeast(1))
    }

    /** Width across [degrees] of view at [distance]. */
    fun span(degrees: Float, distance: Float): Float = 2 * distance * tan(Math.toRadians(degrees / 2.0)).toFloat()

    /** The captions' strip: as wide as most of the screen, two lines tall, just under its foot. */
    data class Captions(val widthM: Float, val heightM: Float, val belowMiddleM: Float, val widthDp: Float)

    fun captions(spec: Spec): Captions {
        // A line about 1.8° tall, as subtitles are read on a cinema screen, two of them.
        val line = span(1.8f, spec.distanceM)
        val height = line * 2.6f
        val width = spec.widthM * 0.9f
        return Captions(width, height, spec.heightM / 2 + height / 2 + 0.04f, width / line * 40f)
    }
}
