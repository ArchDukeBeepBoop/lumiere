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
