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
 * What a box is made of, beyond its colour: a [texture] (a drawable from
 * Scripts/textures.py), repeated every [across] metres along the box's long
 * side and every [up] metres up it (or, for a flat box such as a floor, its
 * short side); 0 lays it once across. The part's colour, lit by the house
 * lights and the film, is multiplied over it.
 */
data class Surface(val texture: Int, val across: Float, val up: Float) {
    /** How many times the texture repeats each way on a box [w] × [h] × [d]. */
    fun repeats(w: Float, h: Float, d: Float): Pair<Float, Float> {
        val long = maxOf(w, d)
        val tall = if (h < minOf(w, d)) minOf(w, d) else h
        fun times(extent: Float, tile: Float) = if (tile <= 0f) 1f else (extent / tile).coerceAtLeast(0.25f)
        return times(long, across) to times(tall, up)
    }
}

/** A box's unlit material: [colour] over its [surface], if it has one. */
fun boxMaterial(colour: Triple<Float, Float, Float>, surface: Surface?, w: Float, h: Float, d: Float): com.meta.spatial.toolkit.Material =
    com.meta.spatial.toolkit.Material().apply {
        baseColor = com.meta.spatial.core.Color4(colour.first, colour.second, colour.third, 1f)
        unlit = true
        if (surface != null) {
            baseTextureAndroidResourceId = surface.texture
            val (u, v) = surface.repeats(w, h, d)
            repeatU = u; repeatV = v
        }
    }
