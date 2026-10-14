package app.lumiere.android.api

/** How a 3D film carries its two eyes in one picture. */
enum class StereoLayout { MONO, SIDE_BY_SIDE, TOP_BOTTOM }

// Tags as rips name them: SBS, HSBS, OU, HOU, between dots, dashes, underscores
// or spaces, so "route", "asbestos" and "south_park" stay flat. The patterns and
// their test cases follow DeadEasy Player (MIT, github.com/jmez11/deadeasy-player).
private val SIDE_BY_SIDE = Regex("""(?:^|[._\- \[(])(?:h?sbs|half[._\- ]?sbs|full[._\- ]?sbs)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)
private val TOP_BOTTOM = Regex("""(?:^|[._\- \[(])(?:h?ou|h?tab|half[._\- ]?ou)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)

/** The layout a name declares, or null when it says nothing about one. */
fun stereoLayoutIn(name: String): StereoLayout? = when {
    SIDE_BY_SIDE.containsMatchIn(name) -> StereoLayout.SIDE_BY_SIDE
    TOP_BOTTOM.containsMatchIn(name) -> StereoLayout.TOP_BOTTOM
    else -> null
}

/**
 * A title's layout: its name's tag first; a title known to be 3D with no tag
 * (in a library called 3D, say) is taken as side by side, as most 3D films are.
 */
fun stereoLayoutOf(item: Item, known3D: Boolean): StereoLayout =
    stereoLayoutIn(item.name) ?: if (known3D) StereoLayout.SIDE_BY_SIDE else StereoLayout.MONO

/**
 * The shape one eye sees, from the whole frame's: a full-width side-by-side
 * film (3840×1080) is two 16:9 pictures, a half-width one (1920×1080) two
 * squeezed ones meant to be shown at the frame's own shape.
 */
fun eyeAspect(layout: StereoLayout, width: Int, height: Int): Float {
    if (width <= 0 || height <= 0) return 16f / 9f
    val frame = width.toFloat() / height
    return when (layout) {
        StereoLayout.SIDE_BY_SIDE -> if (frame >= 3f) frame / 2 else frame
        StereoLayout.TOP_BOTTOM -> if (frame <= 1.2f) frame * 2 else frame
        StereoLayout.MONO -> frame
    }
}

/** How a film's picture wraps round you: flat on a screen, half a sphere (VR180), or all of one (360°). */
enum class Projection { FLAT, HALF_SPHERE, SPHERE }

// "VR180", "180°", "180x180", "360x180", "vr360": unmistakable on their own.
private val SAYS_180 = Regex("""(?:^|[._\- \[(])(?:vr ?180|180 ?°|180 ?deg|180x180)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)
private val SAYS_360 = Regex("""(?:^|[._\- \[(])(?:vr ?360|360 ?°|360 ?deg|360x180)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)
// A bare "180" or "360": a film can be called "360" or "180 Days", so only with an equirect picture's shape.
private val BARE_180 = Regex("""(?:^|[._\- \[(])180(?:[._\- \])]|$)""")
private val BARE_360 = Regex("""(?:^|[._\- \[(])360(?:[._\- \])]|$)""")
// VR files' eye tags, beside the 3D rips' SBS and OU.
private val VR_LR = Regex("""(?:^|[._\- \[(])(?:lr|3dh)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)
private val VR_TB = Regex("""(?:^|[._\- \[(])(?:tb|3dv)(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)
private val VR_MONO = Regex("""(?:^|[._\- \[(])mono(?:[._\- \])]|$)""", RegexOption.IGNORE_CASE)

/** Whether a [width] × [height] picture is the shape an equirect one is: 2:1 or square, give or take 3%. */
private fun equirectShaped(width: Int, height: Int): Boolean {
    if (width <= 0 || height <= 0) return false
    val r = width.toFloat() / height
    return kotlin.math.abs(r - 2f) < 0.06f || kotlin.math.abs(r - 1f) < 0.03f
}

/**
 * How a film wraps round you, from its [names] (title, file name) and its
 * picture's size: an explicit VR180 or 360° tag says so outright; a bare
 * "180" or "360" counts only beside a VR eye tag (LR, TB, mono…) or when
 * the picture is equirect-shaped, so a film called "360" still plays on a
 * screen.
 */
fun projectionIn(names: List<String>, width: Int, height: Int): Projection {
    val text = names.joinToString(" ")
    // A picture of the right shape, or a VR eye tag beside the number, makes a bare number count.
    val shaped = equirectShaped(width, height) || VR_LR.containsMatchIn(text) || VR_TB.containsMatchIn(text) ||
        VR_MONO.containsMatchIn(text) || stereoLayoutIn(text) != null
    return when {
        SAYS_180.containsMatchIn(text) -> Projection.HALF_SPHERE
        SAYS_360.containsMatchIn(text) -> Projection.SPHERE
        shaped && BARE_180.containsMatchIn(text) -> Projection.HALF_SPHERE
        shaped && BARE_360.containsMatchIn(text) -> Projection.SPHERE
        else -> Projection.FLAT
    }
}

/**
 * The eyes of a 180° or 360° film: its tag if it has one (LR, TB, SBS, OU,
 * 3DH, 3DV, mono); otherwise its shape — a square 360° is top and bottom, a
 * 2:1 one a single picture; a 2:1 180° is side by side, a square one single.
 */
fun surroundEyes(names: List<String>, projection: Projection, width: Int, height: Int): StereoLayout {
    val text = names.joinToString(" ")
    stereoLayoutIn(text)?.let { return it }
    if (VR_LR.containsMatchIn(text)) return StereoLayout.SIDE_BY_SIDE
    if (VR_TB.containsMatchIn(text)) return StereoLayout.TOP_BOTTOM
    if (VR_MONO.containsMatchIn(text)) return StereoLayout.MONO
    val square = width > 0 && height > 0 && kotlin.math.abs(width.toFloat() / height - 1f) < 0.03f
    return when (projection) {
        Projection.SPHERE -> if (square) StereoLayout.TOP_BOTTOM else StereoLayout.MONO
        Projection.HALF_SPHERE -> if (square) StereoLayout.MONO else StereoLayout.SIDE_BY_SIDE
        Projection.FLAT -> StereoLayout.MONO
    }
}
