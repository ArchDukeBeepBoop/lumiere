package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.eyeAspect
import app.lumiere.android.player.Theater
import kotlin.math.tan

/**
 * The Theater's screen as numbers. Five sizes, each a share of your view
 * (40° to 92° across) rather than metres, so a size feels the same in any
 * place; each place sets how far away the screen is, so the cinema's is a
 * true cinema screen many metres off and your room's a big TV. The screen
 * takes the film's own shape (2.39:1 is wide and low, 16:9 taller), and in
 * the cinema you sit high in a raked hall, so even the largest screen's
 * middle is near your eye line. Pure, so it's tested without a headset.
 */
object TheaterGeometry {
    /** How much of your view each size fills, across. */
    val SIZE_DEGREES = floatArrayOf(40f, 52f, 64f, 78f, 92f)

    /** How far the screen stands, by place. */
    fun distance(place: Stage.Place): Float = when (place) {
        Stage.Place.ROOM -> 3.0f
        Stage.Place.CINEMA -> 14f
        Stage.Place.VOID -> 9f
    }

    /** How far above your eyes the screen's middle sits, by place: in your room a touch below, as a TV. */
    fun aboveEyes(place: Stage.Place): Float = when (place) {
        Stage.Place.ROOM -> -0.05f
        Stage.Place.CINEMA -> 0.3f
        Stage.Place.VOID -> 0.1f
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

    /** The screen for [request], [place], [size] and [curved]. */
    fun spec(request: Theater.Request, place: Stage.Place, size: Int, curved: Boolean): Spec {
        val (pw, ph) = pictureSize(request)
        if (request.projection != Projection.FLAT)
            return Spec(request.projection, request.eyes, 0f, 0f, null, SPHERE_RADIUS_M, 0f, pw, ph)
        val d = distance(place)
        val degrees = SIZE_DEGREES[size.coerceIn(0, SIZE_DEGREES.lastIndex)]
        val radians = Math.toRadians(degrees.toDouble()).toFloat()
        // Curved, the arc spans the angle; flat, the chord does.
        val width = if (curved) d * radians else 2 * d * tan(radians / 2)
        val aspect = eyeAspect(request.eyes, request.width, request.height).coerceIn(1.2f, 2.8f)
        return Spec(request.projection, request.eyes, width, width / aspect, if (curved) d else null,
            d, aboveEyes(place), pw, ph)
    }

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
     * The captions' panel for a screen: a band over its foot, 60% of its
     * width and a quarter of its height, just in front of it, so the words
     * keep the screen's scale. Width, height, how far up from the screen's
     * middle its own middle sits, and how far in front.
     */
    fun captions(spec: Spec): FloatArray {
        if (spec.projection != Projection.FLAT) return floatArrayOf(2.0f, 0.5f, -0.55f, 0f)
        val w = spec.widthM * 0.6f
        val h = spec.heightM * 0.25f
        return floatArrayOf(w, h, -spec.heightM / 2 + h / 2 + spec.heightM * 0.03f, 0.04f)
    }

    /** For 180° and 360°: captions this far in front of you. */
    const val SPHERE_CAPTIONS_DISTANCE_M = 2.5f
}
