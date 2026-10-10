package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AuditoriumTest {
    private val eyes = 1.2f

    /** The hall for each size, for a 16:9 film and a 2.39:1 one, as the Theater builds it. */
    private fun halls() = listOf(1920 to 1080, 1920 to 804).flatMap { (w, h) ->
        (0 until Stage.SCREEN_SIZES).map { size ->
            val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, w, h), Stage.Place.CINEMA, size, curved = false)
            val middle = eyes + spec.aboveEyesM
            Triple(spec, middle, Auditorium.build(spec.widthM, spec.heightM, middle, spec.distanceM, eyes))
        }
    }

    @Test fun nothingStandsWhereYouAre() {
        halls().forEach { (spec, _, parts) ->
            parts.forEach { p ->
                if (overlaps(p, -0.6f, 0.6f, 0.05f, 2.0f, -0.4f, 0.4f)) fail("${p.kind} at ${p.x},${p.y},${p.z} is where you sit (${spec.widthM} m screen)")
            }
        }
    }

    @Test fun everySightlineToTheScreenIsClear() {
        halls().forEach { (spec, middle, parts) ->
            val blockers = parts.filter { it.kind !in setOf(Auditorium.Kind.MASK, Auditorium.Kind.SCREEN_WALL) }
            for (fx in listOf(-0.48f, 0f, 0.48f)) for (fy in listOf(-0.47f, 0f, 0.45f)) {
                val tx = fx * spec.widthM
                val ty = middle + fy * spec.heightM
                val tz = spec.distanceM - 0.01f
                blockers.forEach { p ->
                    if (segmentHits(p, 0f, eyes, 0f, tx, ty, tz))
                        fail("${p.kind} at (${p.x}, ${p.y}, ${p.z}) hides the screen at ($tx, $ty) — ${"%.1f".format(spec.widthM)} m wide")
                }
            }
        }
    }

    @Test fun theScreenStandsOnItsStageUnderTheCeiling() {
        halls().forEach { (spec, middle, parts) ->
            val stage = parts.single { it.kind == Auditorium.Kind.STAGE }
            assertTrue("stage below the screen's foot", stage.top <= middle - spec.heightM / 2)
            val ceiling = parts.single { it.kind == Auditorium.Kind.CEILING }
            assertTrue("ceiling above the screen", ceiling.bottom > middle + spec.heightM / 2)
            assertTrue("a few draw calls' worth: ${parts.size}", parts.size < 150)
        }
    }

    @Test fun theRakeStaysBetweenAHallsAndAStadiums() {
        listOf(-1f, -3.4f, -6.6f, -20f).forEach { bottom ->
            val r = Auditorium.rakeFor(bottom, 9)
            assertTrue("rake $r", r in Auditorium.MIN_RAKE..Auditorium.MAX_RAKE)
        }
    }

    private fun overlaps(p: Auditorium.Part, x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float) =
        p.x - p.w / 2 < x1 && p.x + p.w / 2 > x0 && p.bottom < y1 && p.top > y0 && p.back < z1 && p.front > z0

    /** Whether the segment from (ax, ay, az) to (bx, by, bz) passes through the box (slab test). */
    private fun segmentHits(p: Auditorium.Part, ax: Float, ay: Float, az: Float, bx: Float, by: Float, bz: Float): Boolean {
        var t0 = 0f; var t1 = 1f
        val a = floatArrayOf(ax, ay, az); val d = floatArrayOf(bx - ax, by - ay, bz - az)
        val lo = floatArrayOf(p.x - p.w / 2, p.bottom, p.back); val hi = floatArrayOf(p.x + p.w / 2, p.top, p.front)
        for (i in 0..2) {
            if (kotlin.math.abs(d[i]) < 1e-6f) { if (a[i] <= lo[i] || a[i] >= hi[i]) return false; continue }
            var ta = (lo[i] - a[i]) / d[i]; var tb = (hi[i] - a[i]) / d[i]
            if (ta > tb) { val t = ta; ta = tb; tb = t }
            t0 = maxOf(t0, ta); t1 = minOf(t1, tb)
            if (t0 >= t1) return false
        }
        return true
    }
}
