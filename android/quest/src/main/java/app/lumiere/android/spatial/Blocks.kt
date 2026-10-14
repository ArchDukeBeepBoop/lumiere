package app.lumiere.android.spatial

/**
 * One box of a place built round your seat (the cabin, the lakeside's
 * pontoon): what it is, its middle and its size, in metres. Laid out as
 * Auditorium's parts are, in your seat's own frame: you at the origin on the
 * real floor, facing +Z, your left +X.
 */
data class Block<K>(val kind: K, val x: Float, val y: Float, val z: Float, val w: Float, val h: Float, val d: Float) {
    val top get() = y + h / 2
    val bottom get() = y - h / 2
    val front get() = z + d / 2
    val back get() = z - d / 2

    companion object {
        /** The box between two corners: from [x0] to [x1] across, [y0] to [y1] up, [z0] to [z1] ahead. */
        fun <K> between(kind: K, x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float) =
            Block(kind, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0)
    }
}

/**
 * A colour under the house lights at [level] (1 up, about 0.12 during a
 * film), with the film's [tint] spilling onto it by [spill] (how squarely it
 * faces the screen) as they go down: the cinema hall's light
 * (Auditorium.colour), for any place. It stays visible in the dark.
 */
fun houseLit(base: Triple<Float, Float, Float>, spill: Float, level: Float, tint: Triple<Float, Float, Float>?): Triple<Float, Float, Float> {
    val (r, g, b) = base
    val house = 0.3f + 0.7f * level
    val (tr, tg, tb) = tint ?: Triple(0.5f, 0.5f, 0.55f)
    val s = spill * (1f - level) * 0.35f
    fun mix(base: Float, t: Float) = (base * house + t * s).coerceIn(0f, 1f)
    return Triple(mix(r, tr), mix(g, tg), mix(b, tb))
}

/**
 * What a part is made of, beyond its colour: a [texture] (a drawable from
 * Scripts/textures.py, mostly grey), one repeat [across] metres wide and
 * [up] metres tall, so it keeps its real scale on every face; 0 lays it
 * once across the face that way (a picture, a row of spines). The part's colour, lit by the house lights and the film,
 * multiplies it (ModelMeshes.light).
 */
data class Surface(val texture: Int, val across: Float, val up: Float)

/** sRGB to linear light, as the headset's shaders take a material's colour. */
fun linear(c: Float): Float = if (c <= 0.04045f) c / 12.92f else Math.pow(((c + 0.055f) / 1.055f).toDouble(), 2.4).toFloat()

/**
 * A modelled part's unlit material, made once: its [surface]'s texture
 * (light grey, the colour multiplied over it later), or for a plain part
 * its colour as first lit, [first].
 */
fun partMaterial(first: Triple<Float, Float, Float>, surface: Surface?): com.meta.spatial.toolkit.Material =
    com.meta.spatial.toolkit.Material().apply {
        unlit = true
        if (surface != null) {
            baseColor = com.meta.spatial.core.Color4(1f, 1f, 1f, 1f)
            baseTextureAndroidResourceId = surface.texture
        } else baseColor = com.meta.spatial.core.Color4(first.first, first.second, first.third, 1f)
    }

/**
 * The albedo that shows [now] on a part made with [partMaterial]: over a
 * texture, the colour itself; on a plain part, the share of its first
 * colour [first] that [now] is, so if the light never arrives it keeps that
 * first colour rather than going white. Linear, each 0..1.
 */
fun albedo(now: Triple<Float, Float, Float>, first: Triple<Float, Float, Float>, textured: Boolean): FloatArray {
    fun ch(n: Float, f: Float): Float = when {
        textured -> linear(n)
        linear(f) < 1e-5f -> 1f
        else -> (linear(n) / linear(f)).coerceIn(0f, 1f)
    }
    return floatArrayOf(ch(now.first, first.first), ch(now.second, first.second), ch(now.third, first.third))
}
