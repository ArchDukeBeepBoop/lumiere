package app.lumiere.android.spatial

/**
 * Light that follows the film, as Apple's environments take on the film's
 * colour: the place's picture tinted toward the film's own colours. The
 * headset draws the film itself, so its frames never reach the app; the
 * colour comes from the title's backdrop instead, averaged from a tiny copy,
 * once per film. Pure but for [fetch], so it's tested without a headset.
 */
object FilmLight {
    data class Rgb(val r: Float, val g: Float, val b: Float)

    /** Settings › Headset › Light follows the film; set by the room. */
    var enabled: () -> Boolean = { true }

    /** How far the light leans toward the film's colour: a cast, never a wash. */
    const val STRENGTH = 0.35f

    /** The albedo for a picture at [brightness] under [tint]: white leaned toward the colour, kept as bright. */
    fun light(brightness: Float, tint: Rgb?): Triple<Float, Float, Float> {
        if (tint == null) return Triple(brightness, brightness, brightness)
        // The colour at full strength (its brightest channel 1), so a dark backdrop still tints rather than dims.
        val peak = maxOf(tint.r, tint.g, tint.b).coerceAtLeast(1e-3f)
        fun ch(c: Float) = brightness * (1 - STRENGTH + STRENGTH * (c / peak))
        return Triple(ch(tint.r), ch(tint.g), ch(tint.b))
    }

    /** The colour of the image at [url], through the signed-in [http]; [done] on the main thread, null on failure. */
    fun fetch(http: okhttp3.OkHttpClient, url: String, done: (Rgb?) -> Unit) {
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
            val c = app.lumiere.android.ui.ArtColour.read(http, url)?.let { Rgb(it.r, it.g, it.b) }
            main.post { done(c) }
        }.start()
    }
}
