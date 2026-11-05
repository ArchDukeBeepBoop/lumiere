package app.lumiere.android.ui

/**
 * The tag on a tile in the Quest's window, as Meta's TV app marks immersive
 * titles: 180°, 360° or 3D, read from the title's own words (VR180, 360,
 * SBS, OU…) as whole words, so "Absolution" stays untagged. The theater's
 * StereoDetect goes further, with the picture's shape, once it plays.
 */
object ImmersiveTag {
    private val STEREO = setOf("3d", "sbs", "hsbs", "fsbs", "ou", "hou", "tab", "3d-sbs", "half-sbs", "full-sbs", "half-ou")

    fun of(name: String): String? {
        val words = name.lowercase().split(' ', '.', '_', '[', ']', '(', ')', ',').filter { it.isNotEmpty() }
        val parts = words + words.flatMap { it.split('-') }
        return when {
            parts.any { it == "180" || it == "vr180" } -> "180°"
            parts.any { it == "360" || it == "vr360" } -> "360°"
            parts.any { it in STEREO } -> "3D"
            else -> null
        }
    }
}
