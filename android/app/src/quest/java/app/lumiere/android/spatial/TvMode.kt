package app.lumiere.android.spatial

/**
 * TV Mode: the film's screen on your wall, or pinned in the air, sized as a
 * TV is sold — its diagonal in inches, on a 16:9 panel, from 32″ to 200″. A
 * film wider than 16:9 fills the panel's width, as on a real TV. A wall too
 * small for the size asked takes the largest that fits. Pure, so it's tested
 * without a headset.
 */
object TvMode {
    val INCHES = listOf(32, 43, 50, 55, 65, 75, 85, 98, 100, 120, 150, 200)
    /** 65″, the size most bought. */
    const val DEFAULT = 4

    val NAMES = INCHES.map { "$it″" }

    /** A 16:9 panel's width for a [inches] diagonal, in metres. */
    fun widthM(inches: Int): Float = inches * 0.0254f * 16f / kotlin.math.sqrt(16f * 16f + 9f * 9f)

    /** The panel's width for size [index], kept within [maxWidthM] (what the wall holds); and whether it was cut down. */
    fun fitted(index: Int, maxWidthM: Float): Pair<Float, Boolean> {
        val wanted = widthM(INCHES[index.coerceIn(0, INCHES.lastIndex)])
        return if (wanted <= maxWidthM) wanted to false else maxWidthM to true
    }

    /** The largest size whose panel fits [maxWidthM], for saying so when a wall is small; null if none does. */
    fun largestFitting(maxWidthM: Float): Int? = INCHES.lastOrNull { widthM(it) <= maxWidthM }
}
