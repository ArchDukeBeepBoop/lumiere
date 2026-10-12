package app.lumiere.android.spatial

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A baked place's light: lit, exactly as baked; down for a film, dim but
 * there and taking the picture's colour on each side; lamps going down with
 * the house lights, signs staying lit.
 */
class BakedLightTest {
    @Test fun litItLooksAsBaked() {
        assertArrayEquals(floatArrayOf(1f, 1f, 1f), BakedLight.albedo(BakedLight.Kind.SURFACE, 1f, Triple(1f, 0f, 0f)), 1e-5f)
        assertArrayEquals(floatArrayOf(1f, 1f, 1f), BakedLight.albedo(BakedLight.Kind.LAMP, 1f, null), 1e-5f)
    }

    @Test fun inAFilmTheHallIsDimAndTakesThePicturesColour() {
        val red = BakedLight.albedo(BakedLight.Kind.SURFACE, 0.12f, Triple(1f, 0f, 0f))
        val dark = BakedLight.albedo(BakedLight.Kind.SURFACE, 0.12f, Triple(0f, 0f, 0f))
        assertTrue("dim: ${red.toList()}", red.all { it < 0.4f })
        assertTrue("but there: ${dark.toList()}", dark.all { it > 0.04f })
        assertTrue("red on the walls", red[0] > red[1] * 1.5f)
        assertEquals(red[1], dark[1], 1e-5f)
    }

    @Test fun lampsGoDownAndSignsStayLit() {
        val lamp = BakedLight.albedo(BakedLight.Kind.LAMP, 0.12f, Triple(1f, 1f, 1f))
        assertTrue(lamp[0] < 0.1f)
        assertArrayEquals(floatArrayOf(1f, 1f, 1f), BakedLight.albedo(BakedLight.Kind.GLOW, 0.12f, Triple(1f, 0f, 0f)), 0f)
    }

    @Test fun eachMaterialIsKnownByItsName() {
        assertEquals(BakedLight.Kind.SURFACE, BakedLight.kindOf("hall/baked"))
        assertEquals(BakedLight.Kind.LAMP, BakedLight.kindOf("lamp:sconce"))
        assertEquals(BakedLight.Kind.GLOW, BakedLight.kindOf("glow:exit"))
        assertEquals(Side.LEFT, BakedLight.sideOf("walls@L/baked"))
        assertEquals(Side.RIGHT, BakedLight.sideOf("walls@R/baked"))
        assertEquals(Side.MIDDLE, BakedLight.sideOf("seats_front/baked"))
    }
}
