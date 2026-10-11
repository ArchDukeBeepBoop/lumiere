package app.lumiere.android.spatial

import kotlin.math.cos
import kotlin.math.sin

/** A point in your seat's frame: you at the origin on the floor, facing +Z. */
data class Point(val x: Float, val y: Float, val z: Float)

/**
 * Points on the screen of [spec] seen from eyes at [eyeY], in your seat's
 * frame, just in front of its surface: across it at each of [across] (-0.5
 * one edge … 0.5 the other) and up it at each of [up] (-0.5 its foot … 0.5
 * its top). A curved screen's points go round its curve, centred on you.
 */
fun screenPoints(spec: TheaterGeometry.Spec, eyeY: Float, across: List<Float>, up: List<Float>): List<Point> {
    val middle = eyeY + spec.aboveEyesM
    return across.flatMap { fx ->
        up.map { fy ->
            val y = middle + fy * spec.heightM
            val r = spec.radiusM
            if (r == null) Point(fx * spec.widthM, y, spec.distanceM - 0.01f)
            else {
                val a = fx * spec.widthM / r
                Point((r - 0.01f) * sin(a), y, (r - 0.01f) * cos(a))
            }
        }
    }
}

/** Whether the segment from [a] to [b] passes through the box [p] (slab test). */
fun segmentHits(p: Block<*>, a: Point, b: Point): Boolean {
    var t0 = 0f; var t1 = 1f
    val from = floatArrayOf(a.x, a.y, a.z); val d = floatArrayOf(b.x - a.x, b.y - a.y, b.z - a.z)
    val lo = floatArrayOf(p.x - p.w / 2, p.bottom, p.back); val hi = floatArrayOf(p.x + p.w / 2, p.top, p.front)
    for (i in 0..2) {
        if (kotlin.math.abs(d[i]) < 1e-6f) { if (from[i] <= lo[i] || from[i] >= hi[i]) return false; continue }
        var ta = (lo[i] - from[i]) / d[i]; var tb = (hi[i] - from[i]) / d[i]
        if (ta > tb) { val t = ta; ta = tb; tb = t }
        t0 = maxOf(t0, ta); t1 = minOf(t1, tb)
        if (t0 >= t1) return false
    }
    return true
}

/** Whether [p] takes up any of the box from ([x0], [y0], [z0]) to ([x1], [y1], [z1]). */
fun overlaps(p: Block<*>, x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float) =
    p.x - p.w / 2 < x1 && p.x + p.w / 2 > x0 && p.bottom < y1 && p.top > y0 && p.back < z1 && p.front > z0
