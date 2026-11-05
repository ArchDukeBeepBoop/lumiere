package app.lumiere.android.spatial

import app.lumiere.android.R
import kotlin.math.tan

/**
 * Where a film plays: your own room (passthrough), or a place round you —
 * each a 360° picture drawn from its seat, shown as the sky is. The cinema,
 * the cabin and the space station have a screen of their own in their
 * picture, and you sit in the back row (the user's choice, 2026-10-27; only
 * that seat's picture comes with the app): the film's screen is theirs, at
 * its size. Elsewhere it stands at the place's distance at your Screen Size.
 *
 * A 360° picture reads as far off to your eyes, so a screen at its true
 * distance stood out in front of the one drawn there; it's put [FAR] times
 * further and as many times larger, the same share of your view at the
 * picture's depth. Pure, so it's tested without a headset. Measurements
 * from the spatial app (docs/quest/HANDOVER.md §4).
 */
enum class Place(
    val label: String,
    /** The picture round you; none in your room or the dark. */
    val picture: Int?,
    /** The same with the lights down, for a film; null: [picture] dimmed instead. */
    val dark: Int?,
    /** The screen drawn in the picture, as seen from the back row: its width, distance and height over your eyes. */
    val drawn: Drawn?,
    /** Elsewhere: how far the screen stands, and how far above your eyes its middle. */
    val distanceM: Float,
    val aboveEyesM: Float,
) {
    ROOM("Your Room", null, null, null, TheaterGeometry.ROOM_DISTANCE_M, TheaterGeometry.ROOM_ABOVE_EYES_M),
    CINEMA("Cinema", R.drawable.pano_cinema_s0, R.drawable.pano_cinema_s0_dark, Drawn(20f, 11.25f, 19.02f, -0.635f), 0f, 0f),
    CABIN("Cabin", R.drawable.pano_cabin_s0, R.drawable.pano_cabin_s0_dark, Drawn(5.5f, 5.5f * 9f / 16f, 5.28f, 0.52f), 0f, 0f),
    STATION("Space Station", R.drawable.pano_station_s0, R.drawable.pano_station_s0_dark, Drawn(4f, 4f * 9f / 16f, 3.84f, 0.3f), 0f, 0f),
    LAKE("Lakeside", R.drawable.pano_lake, R.drawable.pano_lake_dark, null, 14f, 0.9f),
    CLOUDS("Above the Clouds", R.drawable.pano_clouds, R.drawable.pano_clouds_dark, null, 16f, 0.9f),
    MOON("The Moon", R.drawable.pano_moon, R.drawable.pano_moon_dark, null, 18f, 1.2f),
    SPACE("Space", R.drawable.lumiere_starfield, null, null, 12f, 0.2f),
    DARK("The Dark", null, null, null, 10f, 0.1f);

    /** A screen drawn in a place's picture: as wide and tall, as far, and as high as it is there. */
    data class Drawn(val widthM: Float, val heightM: Float, val distanceM: Float, val aboveEyesM: Float)

    /** Whether you see your own room here (passthrough). */
    val passthrough: Boolean get() = this == ROOM

    /** Whether the picture round you is a 360° view of somewhere, which reads as far off. */
    val panorama: Boolean get() = picture != null && this != SPACE

    /**
     * The film's screen here for a [videoWidth] × [videoHeight] picture at [size]:
     * the place's own screen where it has one (the film fitted inside it), else
     * a share of your view at the place's distance — [FAR] times further and
     * larger in a 360° place.
     */
    fun screen(videoWidth: Int, videoHeight: Int, size: Int): TheaterGeometry.Spec {
        val aspect = if (videoWidth > 0 && videoHeight > 0) videoWidth.toFloat() / videoHeight else 16f / 9f
        val far = if (panorama) FAR else 1f
        val d = drawn
        if (d != null) {
            val (w, h) = if (aspect >= d.widthM / d.heightM) d.widthM to d.widthM / aspect else d.heightM * aspect to d.heightM
            return TheaterGeometry.sized(w * far, videoWidth, videoHeight, d.distanceM * far).copy(aboveEyesM = d.aboveEyesM * far)
        }
        val degrees = TheaterGeometry.SIZE_DEGREES[size.coerceIn(0, TheaterGeometry.SIZE_DEGREES.lastIndex)]
        val width = 2 * distanceM * tan(Math.toRadians(degrees / 2.0)).toFloat()
        return TheaterGeometry.sized(width * far, videoWidth, videoHeight, distanceM * far).copy(aboveEyesM = aboveEyesM * far)
    }

    /** The picture to show for a film (lights down) or not; and how bright, where there's no dark picture. */
    fun pictureFor(film: Boolean): Pair<Int, Float>? {
        val lit = picture ?: return null
        if (!film) return lit to 1f
        return dark?.let { it to 1f } ?: (lit to if (drawn != null) DIMMED else 1f)
    }

    companion object {
        /** How much further, and larger, a screen stands in a 360° place, to sit at the picture's depth. */
        const val FAR = 6f
        /** A lit room's picture kept this bright for a film, as house lights going down. */
        const val DIMMED = 0.32f

        fun named(name: String?): Place = entries.firstOrNull { it.name == name } ?: ROOM
    }
}
