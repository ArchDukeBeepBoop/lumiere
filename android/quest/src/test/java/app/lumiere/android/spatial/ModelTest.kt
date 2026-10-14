package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The modelled places: each part is made within its own bounds (which is
 * what the sightline tests check), shapes are shaded by the way they face,
 * a picture lies once across its face, and the cinema's front curtain
 * covers the screen drawn and clears it gathered.
 */
class ModelTest {
    private val eyes = 1.2f

    @After fun open() { FrontCurtain.closed = 0f }

    private fun halls() = listOf(false, true).flatMap { fill -> listOf(1920 to 1080, 1920 to 804).flatMap { (w, h) ->
        (0 until Stage.SCREEN_SIZES).map { size ->
            val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, w, h), Stage.Place.CINEMA, size, curved = false, scopeFill = fill)
            spec to Auditorium.build(spec.widthM, spec.heightM, eyes + spec.aboveEyesM, spec.distanceM, eyes)
        } }
    }

    @Test fun everyCinemaPartIsMadeWithinItsBounds() {
        halls().forEach { (spec, parts) ->
            parts.forEach { b ->
                val m = Modeller<Auditorium.Kind>(tiles = { k -> Auditorium.surface(k)?.let { it.across to it.up } })
                m.part(b.kind, b.x)
                Auditorium.shape(b, m)
                assertTrue("${b.kind} makes something", m.meshes.values.sumOf { it.indexCount } > 0)
                m.meshes.values.forEach { mesh ->
                    val e = 0.03f
                    if (mesh.min[0] < b.x - b.w / 2 - e || mesh.max[0] > b.x + b.w / 2 + e ||
                        mesh.min[1] < b.bottom - e || mesh.max[1] > b.top + e ||
                        mesh.min[2] < b.back - e || mesh.max[2] > b.front + e)
                        fail("${b.kind} at (${b.x}, ${b.y}, ${b.z}) spills out of its bounds: " +
                            "${mesh.min.toList()}..${mesh.max.toList()} (${spec.widthM} m screen)")
                }
            }
        }
    }

    @Test fun theHallIsAFewDozenMeshesNotHundredsOfBoxes() {
        halls().forEach { (_, parts) ->
            val m = Modeller<Auditorium.Kind>({ k -> Auditorium.surface(k)?.let { it.across to it.up } }, Auditorium::shaded, Auditorium::sided)
            parts.filter { it.kind != Auditorium.Kind.TABS }.forEach { m.part(it.kind, it.x); Auditorium.shape(it, m) }
            // Fewer than the boxes the hall was made of before, each one draw call.
            assertTrue("${m.meshes.size} meshes", m.meshes.size <= 120)
            val vertices = m.meshes.values.sumOf { it.vertices }
            assertTrue("$vertices vertices", vertices < 400_000)
            // Real seats, not benches: many to a row.
            val seats = parts.filter { it.kind == Auditorium.Kind.SEAT }
            assertTrue(seats.isNotEmpty())
        }
    }

    @Test fun theSeatsBeforeYouStandDarkAgainstThePicture() {
        val m = Modeller<Auditorium.Kind>()
        m.part(Auditorium.Kind.SEAT, 0f)
        Auditorium.shape(Block.between(Auditorium.Kind.SEAT, -2f, 2f, -1f, -1f + Auditorium.SEATS_TALL, 0.65f, 1.38f), m)
        val facings = m.meshes.keys.filter { it.kind == Auditorium.Kind.SEAT_FRAME }.map { it.facing }.toSet()
        assertTrue("the shells' backs face you: $facings", Facing.VIEWERWARD in facings)
        val dark = Facing.VIEWERWARD.shade(Triple(0.5f, 0.1f, 0.1f), 0.12f)
        val lit = Facing.SCREENWARD.shade(Triple(0.5f, 0.1f, 0.1f), 0.12f)
        assertTrue(dark.first < lit.first / 3)
        // Under full house lights the tops are brightest and the undersides darkest.
        assertTrue(Facing.UP.shade(Triple(1f, 1f, 1f), 1f).first > Facing.SIDEWAYS.shade(Triple(1f, 1f, 1f), 1f).first)
        assertTrue(Facing.DOWN.shade(Triple(1f, 1f, 1f), 1f).first < Facing.SIDEWAYS.shade(Triple(1f, 1f, 1f), 1f).first)
    }

    @Test fun aPictureLiesOnceAcrossItsFaceTheRightWayUp() {
        val m = Modeller<String>(tiles = { if (it == "art") 0f to 0f else 1f to 1f })
        m.part("art", 0f)
        // A canvas on a wall before you, facing you (−Z).
        m.box(-0.4f, 0.4f, 1.0f, 1.6f, 2.0f, 2.02f)
        val front = m.meshes.entries.single { it.key.facing == Facing.VIEWERWARD }.value
        val uv = front.uvs(); val p = front.positions()
        val us = uv.filterIndexed { i, _ -> i % 2 == 0 }; val vs = uv.filterIndexed { i, _ -> i % 2 == 1 }
        assertEquals(0f, us.min(), 1e-4f); assertEquals(1f, us.max(), 1e-4f)
        assertEquals(0f, vs.min(), 1e-4f); assertEquals(1f, vs.max(), 1e-4f)
        // Its top edge takes the picture's top (v 0), and its left as you face it (−X... your right is −X, so
        // as you look at it the picture's left is at +X).
        for (i in 0 until front.vertices) {
            val y = p[3 * i + 1]; val x = p[3 * i]
            assertEquals(if (y > 1.3f) 0f else 1f, uv[2 * i + 1], 1e-4f)
            assertEquals(if (x > 0f) 0f else 1f, uv[2 * i], 1e-4f)
        }
    }

    @Test fun aTiledSurfaceKeepsItsScale() {
        val m = Modeller<String>(tiles = { 0.5f to 0.5f })
        m.part("carpet", 0f)
        m.box(0f, 2f, -0.1f, 0f, 0f, 3f)
        val top = m.meshes.entries.single { it.key.facing == Facing.UP }.value
        val us = top.uvs().filterIndexed { i, _ -> i % 2 == 0 }
        assertEquals(4f, us.max() - us.min(), 1e-4f)
    }

    @Test fun aTiltedBackLeansAwayFromTheScreen() {
        val m = Modeller<String>()
        m.part("back", 0f)
        m.tilted(15f, 0f, 0f) { m.box(-0.2f, 0.2f, 0f, 1f, -0.05f, 0.05f) }
        val all = m.meshes.values
        assertTrue("the top goes back toward you", all.minOf { it.min[2] } < -0.2f)
        assertTrue(all.maxOf { it.max[1] } < 1f)
    }

    @Test fun theFrontCurtainCoversTheScreenDrawnAndClearsItGathered() {
        halls().forEach { (spec, parts) ->
            val strips = parts.filter { it.kind == Auditorium.Kind.TABS }
            assertEquals(2 * Auditorium.TAB_STRIPS, strips.size)
            val half = spec.widthM / 2
            // Gathered: every strip beyond the screen's edges.
            strips.forEach { s -> assertTrue("${s.x} ± ${s.w / 2} beside a ${spec.widthM} m screen", kotlin.math.abs(s.x) - s.w / 2 > half) }
            // Drawn: every point across the screen behind some strip.
            FrontCurtain.closed = 1f
            var x = -half
            while (x <= half) {
                assertTrue("a gap at $x", strips.any { s -> val c = s.x + FrontCurtain.sway(s).dx; x >= c - s.w / 2 - 1e-3f && x <= c + s.w / 2 + 1e-3f })
                x += 0.05f
            }
            // And from top to foot.
            strips.forEach { s -> assertTrue(s.top >= eyes + spec.aboveEyesM + spec.heightM / 2 && s.bottom <= eyes + spec.aboveEyesM - spec.heightM / 2) }
            FrontCurtain.closed = 0f
        }
    }
}
