package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The lakeside's pontoon: under you at your floor, with its beams, posts, bollards and lanterns, and never over the screen's foot. */
class DockTest {
    private val planks = setOf(Dock.Kind.PLANK, Dock.Kind.PLANK_WORN)

    /** The lakeside's screen for every size, flat and curved, 16:9 and 2.39:1 and the squarest, from a sofa, a chair and standing. */
    private fun views() = listOf(1920 to 1080, 1920 to 804, 1080 to 1080).flatMap { (w, h) ->
        listOf(false, true).flatMap { curved ->
            (0 until Stage.SCREEN_SIZES).flatMap { size ->
                val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, w, h), Stage.Place.LAKE, size, curved)
                listOf(0.9f, 1.2f, 1.7f).map { eyes -> Triple(spec, eyes, Dock.build(eyes, TheaterGeometry.footSlope(spec))) }
            }
        }
    }

    @Test fun theDeckIsUnderYouAtYourFloor() {
        val parts = Dock.build(1.2f)
        val deck = parts.filter { it.kind in planks }
        assertTrue("8 to 12 planks: ${deck.size}", deck.size in 8..12)
        deck.forEach { assertEquals("every plank's top at your floor", 0f, it.top, 1e-5f) }
        assertTrue("a plank under your seat", deck.any { it.x - it.w / 2 < -0.5f && it.x + it.w / 2 > 0.5f && it.back <= 0f && it.front >= 0f })
        assertEquals("about 3 m wide", 3f, deck.maxOf { it.x + it.w / 2 } - deck.minOf { it.x - it.w / 2 }, 0.01f)
        assertEquals("from 1.5 m behind you", -Dock.BEHIND, deck.minOf { it.back }, 0.02f)
        assertEquals("to 5 m ahead", Dock.AHEAD, deck.maxOf { it.front }, 0.02f)
        // Planks with gaps between them, where the water shows.
        val sorted = deck.sortedBy { it.z }
        assertTrue(sorted.zipWithNext().all { (a, b) -> b.back - a.front in 0.01f..0.05f })
    }

    @Test fun itHasEdgeBeamsPostsBollardsAndLanterns() {
        val parts = Dock.build(1.2f)
        assertEquals(2, parts.count { it.kind == Dock.Kind.BEAM })
        assertTrue(parts.filter { it.kind == Dock.Kind.POST }.all { it.top <= -0.2f })
        assertEquals(2, parts.count { it.kind == Dock.Kind.BOLLARD })
        assertEquals(2, parts.count { it.kind == Dock.Kind.LANTERN })
        // No water plane, nothing wider than the pontoon: the sky's lake stays in view all round. Only the
        // boat tied alongside and the fireflies over the water go beyond its edges, and the boat lies low.
        parts.forEach { assertTrue("${it.kind} is no wider than the pontoon", it.w <= 3.3f && it.d <= Dock.AHEAD + Dock.BEHIND) }
        val beyond = setOf(Dock.Kind.HULL, Dock.Kind.HULL_INSIDE, Dock.Kind.THWART, Dock.Kind.OAR, Dock.Kind.FIREFLY)
        parts.filter { it.kind !in beyond }.forEach { assertTrue("${it.kind} keeps to the pontoon", it.x + it.w / 2 <= 1.7f && it.x - it.w / 2 >= -1.7f) }
        assertTrue("the boat lies below the deck", parts.filter { it.kind in beyond - Dock.Kind.FIREFLY }.all { it.top < 0f })
        assertEquals("the lanterns burn on in the dark", Dock.baseColour(Dock.Kind.LANTERN), Dock.colour(Dock.Kind.LANTERN, CinemaLight.PLAYING, null))
        assertTrue("the boards dim for a film", Dock.colour(Dock.Kind.PLANK, CinemaLight.PLAYING, null).first < Dock.colour(Dock.Kind.PLANK, 1f, null).first)
    }

    @Test fun theDeckNeverHidesTheScreensFootOrItsCaptions() {
        val across = listOf(-0.5f, -0.3f, -0.1f, 0f, 0.1f, 0.3f, 0.5f)
        views().forEach { (spec, eyes, parts) ->
            val eye = Point(0f, eyes, 0f)
            screenPoints(spec, eyes, across, listOf(-0.5f, -0.4f, -0.25f, 0f)).forEach { target ->
                // The fireflies are specks that drift past, as real ones do; everything else stays out of the way.
                parts.filter { it.kind != Dock.Kind.FIREFLY }.forEach { p ->
                    if (segmentHits(p, eye, target))
                        fail("${p.kind} at (${p.x}, ${p.y}, ${p.z}) hides the screen at (${target.x}, ${target.y}, ${target.z}): " +
                            "${spec.widthM} m${if (spec.radiusM != null) " curved" else ""}, eyes at $eyes")
                }
            }
            val deck = parts.filter { it.kind in planks }
            assertTrue("still a deck from behind you", deck.minOf { it.back } <= -Dock.BEHIND + 0.02f)
            assertTrue("to before you: ${deck.maxOf { it.front }}", deck.maxOf { it.front } >= Dock.MIN_AHEAD - 0.02f)
        }
    }

    @Test fun theSmallestScreenLeavesTheWholeDeck() {
        val spec = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 1080), Stage.Place.LAKE, 0, false)
        val deck = Dock.build(1.2f, TheaterGeometry.footSlope(spec)).filter { it.kind in planks }
        assertTrue("${deck.maxOf { it.front }} m ahead", deck.maxOf { it.front } > 3.5f)
    }

    @Test fun anEveningOnThePontoon() {
        val parts = Dock.build(1.2f)
        assertEquals("two chairs", 12, parts.count { it.kind == Dock.Kind.CHAIR })
        assertTrue("flames in both lanterns and the jar", parts.count { it.kind == Dock.Kind.FLAME } == 3)
        assertTrue("fireflies over the water", parts.count { it.kind == Dock.Kind.FIREFLY } >= 12)
        // Everything someone left out is beside or behind you, never before you where the screen is.
        val things = setOf(Dock.Kind.CHAIR, Dock.Kind.CRATE, Dock.Kind.MUG, Dock.Kind.JAR, Dock.Kind.COOLER, Dock.Kind.BULB)
        assertTrue(parts.filter { it.kind in things }.all { it.front <= 0f })
        assertTrue("a few draw calls' worth: ${parts.size}", parts.size <= 100)
        // The lanterns' flames move; the deck doesn't.
        assertTrue(Dock.moves(Dock.Kind.FLAME, 1, 1f) != null && Dock.moves(Dock.Kind.PLANK, 1, 1f) == null)
    }
}
