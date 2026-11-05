package app.lumiere.android.spatial

/**
 * What kind of picture a film is, as NEX and the other Quest players tell:
 * flat, 3D side by side or over-under, or 180° or 360° round you. From the
 * title's own words first — SBS, HSBS, LR, OU, TB, 180, 360, as separate
 * words, so "Absolution" and "Tobacco" stay flat — then the picture's shape:
 * two 16:9 frames side by side are over 3.2:1, and a 360° picture is exactly
 * 2:1 at 4K or more. A title's own choice in the player wins over both
 * (ScreenPlace.formatFor). Pure, so it's tested without a headset.
 */
object StereoDetect {
    enum class Format(val label: String) {
        FLAT("Flat"), SBS("Side by Side"), OU("Over-Under"),
        VR180_SBS("180°"), VR360_MONO("360°"), VR360_OU("360° 3D"),
        /** A 3D film watched flat, one eye's picture to both (chosen in the 3D menu, never guessed). */
        SBS_2D("Side by Side, in 2D"), OU_2D("Over-Under, in 2D");

        val stereo: Boolean get() = this == SBS || this == OU || this == VR180_SBS || this == VR360_OU
        val sphere: Boolean get() = this == VR180_SBS || this == VR360_MONO || this == VR360_OU
    }

    private val SIDE = setOf("sbs", "hsbs", "3d-sbs", "half-sbs", "lr", "fsbs", "full-sbs")
    private val OVER = setOf("ou", "hou", "tb", "tab", "half-ou", "half-tab", "fou", "full-ou")

    fun of(name: String, width: Int, height: Int): Format {
        val lower = name.lowercase()
        val words = lower.split(' ', '.', '_', '[', ']', '(', ')', ',').filter { it.isNotEmpty() }.toSet()
        // "3D-SBS" and "Half-SBS" keep their hyphen; the rest split on it too.
        val parts = words + words.flatMap { it.split('-') }.filter { it.isNotEmpty() }
        val side = parts.any { it in SIDE }
        val over = parts.any { it in OVER }
        val has180 = parts.any { it == "180" || it == "vr180" }
        val has360 = parts.any { it == "360" || it == "vr360" }
        when {
            has180 && (side || !over) -> return Format.VR180_SBS
            has360 && over -> return Format.VR360_OU
            has360 -> return Format.VR360_MONO
            side -> return Format.SBS
            over -> return Format.OU
        }
        if (width <= 0 || height <= 0) return Format.FLAT
        if (width >= 3.2f * height) return Format.SBS
        if (width == 2 * height && width >= 3840) return Format.VR360_MONO
        return Format.FLAT
    }

    /**
     * One eye's picture shape: a full side-by-side frame is two pictures wide
     * (each half the width), a half one squeezes them into a normal frame
     * (shown at the frame's shape); over-under the same, up and down.
     */
    fun eyeAspect(format: Format, width: Int, height: Int): Float {
        if (width <= 0 || height <= 0) return 16f / 9f
        val frame = width.toFloat() / height
        return when (format) {
            Format.SBS, Format.SBS_2D -> if (frame >= 3.2f) frame / 2 else frame
            Format.OU, Format.OU_2D -> if (frame <= 1.0f) frame * 2 else frame
            else -> frame
        }
    }
}
