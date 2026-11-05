package app.lumiere.android.ui

import app.lumiere.android.api.Item
import app.lumiere.android.api.Server

/**
 * A title's colour, from its artwork: a tiny copy fetched through the
 * signed-in client and averaged, near-black and near-white left out as they
 * carry no colour. For the Quest's colour ground, which takes on the
 * spotlight's colour, and the theater's light. A few dozen remembered.
 */
object ArtColour {
    data class Rgb(val r: Float, val g: Float, val b: Float)

    private val known = object : LinkedHashMap<String, Rgb?>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Rgb?>) = size > 64
    }

    /** The average of [pixels] (ARGB), or null when none has colour. Pure, so it's tested. */
    fun average(pixels: IntArray): Rgb? {
        var r = 0L; var g = 0L; var b = 0L; var n = 0
        for (p in pixels) {
            val pr = p shr 16 and 0xFF; val pg = p shr 8 and 0xFF; val pb = p and 0xFF
            val max = maxOf(pr, pg, pb); val min = minOf(pr, pg, pb)
            if (max < 24 || min > 232) continue
            r += pr; g += pg; b += pb; n++
        }
        if (n == 0) return null
        return Rgb(r / (255f * n), g / (255f * n), b / (255f * n))
    }

    /** The colour of the image at [url], read through [http]; null on any failure. Blocking: call off the main thread. */
    fun read(http: okhttp3.OkHttpClient, url: String): Rgb? = runCatching {
        http.newCall(okhttp3.Request.Builder().url(url).build()).execute().use { r ->
            r.body?.byteStream()?.let { android.graphics.BitmapFactory.decodeStream(it) }
        }?.let { bmp ->
            val px = IntArray(bmp.width * bmp.height)
            bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
            bmp.recycle()
            average(px)
        }
    }.getOrNull()

    /** [item]'s colour, from its backdrop (else its poster), remembered. */
    suspend fun of(server: Server, item: Item): Rgb? {
        synchronized(known) { if (known.containsKey(item.id)) return known[item.id] }
        val kind = if (item.backdropTag != null) "Backdrop" else "Primary"
        val c = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            read(server.http, server.imageUrl(item.id, kind, item.backdropTag ?: item.primaryTag, 64))
        }
        synchronized(known) { known[item.id] = c }
        return c
    }
}
