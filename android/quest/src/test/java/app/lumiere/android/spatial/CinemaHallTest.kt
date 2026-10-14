package app.lumiere.android.spatial

import app.lumiere.android.Stage
import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.player.Theater
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The cinema as built: each size a seat with its share of your view, the
 * screen's whole foot in sight from every seat over the row in front (and the
 * front row's parapet) whether you sit low or stand, the screen where the
 * hall has it, the curtain covering it drawn and out of sight raised — and
 * the model baked in Blender agreeing with all of it.
 */
class CinemaHallTest {
    private val tv = Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 1080)
    private val eyes = listOf(0.95f, 1.2f, 1.45f, 1.75f)

    @Test fun eachSizeIsASeatWithItsShareOfYourView() {
        TheaterGeometry.SIZE_DEGREES.forEachIndexed { size, degrees ->
            val seen = TheaterGeometry.angleDegrees(CinemaHall.SCREEN_W, CinemaHall.distance(size))
            assertEquals("size $size from row ${CinemaHall.row(size)}", degrees, seen, 2.0f)
        }
        // Larger is nearer, a row further forward.
        assertTrue((1 until Stage.SCREEN_SIZES).all { CinemaHall.distance(it) < CinemaHall.distance(it - 1) })
        assertTrue(CinemaHall.SEAT_ROWS.all { it in 0 until CinemaHall.ROWS })
    }

    @Test fun theScreenIsTheHallsWhereverYouSit() {
        for (size in 0 until Stage.SCREEN_SIZES) for (eye in eyes) {
            val spec = TheaterGeometry.spec(tv, Stage.Place.CINEMA, size, curved = true, scopeFill = true, eyeY = eye)
            assertEquals("never curved", null, spec.radiusM)
            assertEquals(CinemaHall.SCREEN_W, spec.widthM, 1e-4f)
            assertEquals(CinemaHall.distance(size), spec.distanceM, 1e-4f)
            // Its middle where the hall has it, however tall you are: in the hall's frame, your eyes plus aboveEyes.
            assertEquals(CinemaHall.SCREEN_MIDDLE, CinemaHall.floor(size) + eye + spec.aboveEyesM, 1e-4f)
        }
        // A wide film is the screen's width and shorter; a 4:3 one its height and narrower.
        val wide = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, 1920, 804), Stage.Place.CINEMA, 2, false)
        assertEquals(CinemaHall.SCREEN_W, wide.widthM, 1e-4f)
        assertTrue(wide.heightM < CinemaHall.SCREEN_H)
        val square = TheaterGeometry.spec(Theater.Request(Projection.FLAT, StereoLayout.MONO, 1440, 1080), Stage.Place.CINEMA, 2, false)
        assertEquals(CinemaHall.SCREEN_H, square.heightM, 1e-4f)
        assertTrue(square.widthM < CinemaHall.SCREEN_W)
    }

    @Test fun fromTheMiddleRowsTheScreensMiddleIsALittleAboveYourEyes() {
        val above = (0 until Stage.SCREEN_SIZES).map { Math.toDegrees(kotlin.math.atan2(CinemaHall.aboveEyes(it, CinemaHall.SEAT_EYE), CinemaHall.distance(it)).toDouble()) }
        assertTrue("the back row looks level: ${above[0]}°", above[0] in -5.0..2.0)
        assertTrue("the default seat a little up: ${above[TheaterGeometry.DEFAULT_SIZE]}°", above[TheaterGeometry.DEFAULT_SIZE] in 5.0..15.0)
        assertTrue("the front row up, as a front row is: ${above.last()}°", above.last() in 20.0..35.0)
        assertTrue(above.zipWithNext().all { (a, b) -> b > a })
    }

    @Test fun theScreensFootIsInSightFromEverySeat() {
        for (k in 0 until CinemaHall.ROWS) for (eye in eyes) {
            val eyeY = CinemaHall.rowFloor(k) + eye
            val d = CinemaHall.rowDistance(k)
            val slope = (eyeY - CinemaHall.SCREEN_BOTTOM) / d
            if (k == 0) {
                // Over the parapet's cap, at its nearest.
                val ahead = d - (-CinemaHall.PARAPET_Z) - CinemaHall.PARAPET_DEPTH
                val line = eyeY - slope * ahead
                assertTrue("the front row, eyes $eye: the parapet at ${CinemaHall.rowFloor(0) + CinemaHall.PARAPET_TOP} under $line",
                    CinemaHall.rowFloor(0) + CinemaHall.PARAPET_TOP < line)
            } else {
                // Over the seat backs of the row in front.
                val ahead = CinemaHall.PITCH - CinemaHall.SEAT_TOP_BEHIND_EYE
                val line = eyeY - slope * ahead
                val top = CinemaHall.rowFloor(k - 1) + CinemaHall.SEAT_TOP
                assertTrue("row $k, eyes $eye: the seats in front at $top under $line", top < line)
            }
        }
    }

    @Test fun theCurtainCoversTheScreenDrawnAndIsOutOfSightRaised() {
        assertTrue(CinemaHall.CURTAIN_HALF_W > CinemaHall.SCREEN_W / 2)
        assertTrue(CinemaHall.CURTAIN_BOTTOM <= CinemaHall.SCREEN_BOTTOM && CinemaHall.CURTAIN_TOP > CinemaHall.VALANCE_BOTTOM)
        assertTrue("the valance clears the screen", CinemaHall.VALANCE_BOTTOM > CinemaHall.SCREEN_BOTTOM + CinemaHall.SCREEN_H)
        // Raised, its foot is behind the valance (or above the ceiling) from every seat, standing or sitting.
        val foot = CinemaHall.CURTAIN_BOTTOM + CinemaHall.CURTAIN_RISE
        for (k in 0 until CinemaHall.ROWS) for (eye in eyes) {
            val eyeY = CinemaHall.rowFloor(k) + eye
            val eyeZ = -CinemaHall.rowDistance(k)
            val t = (CinemaHall.VALANCE_Z - eyeZ) / (CinemaHall.CURTAIN_FRONT - eyeZ)
            val crossing = eyeY + (foot - eyeY) * t
            assertTrue("row $k, eyes $eye: the raised curtain seen at $crossing", crossing > CinemaHall.VALANCE_BOTTOM)
        }
    }

    @Test fun theHallGoesRoundYouByYourRow() {
        for (size in 0 until Stage.SCREEN_SIZES) {
            val o = CinemaHall.origin(size)
            // Your row's floor is your floor; the screen's face is the distance ahead.
            assertEquals(0f, o[1] + CinemaHall.floor(size), 1e-5f)
            assertEquals(CinemaHall.distance(size), o[2], 1e-5f)
        }
    }

    /** environments/cinema.json, written by Scripts/env/cinema.py with its model: the same hall. */
    @Test fun theBakedModelIsThisHall() {
        val json = File("src/main/assets/environments/cinema.json")
        if (!json.exists()) return
        val o = org.json.JSONObject(json.readText())
        val screen = o.getJSONObject("screen")
        assertEquals(CinemaHall.SCREEN_W.toDouble(), screen.getDouble("width"), 1e-4)
        assertEquals(CinemaHall.SCREEN_H.toDouble(), screen.getDouble("height"), 1e-4)
        assertEquals(CinemaHall.SCREEN_BOTTOM.toDouble(), screen.getDouble("bottom"), 1e-4)
        val rows = o.getJSONObject("rows")
        assertEquals(CinemaHall.ROWS, rows.getInt("count"))
        assertEquals(CinemaHall.NEAREST.toDouble(), rows.getDouble("nearest"), 1e-4)
        assertEquals(CinemaHall.PITCH.toDouble(), rows.getDouble("pitch"), 1e-4)
        assertEquals(CinemaHall.FIRST_FLOOR.toDouble(), rows.getDouble("firstFloor"), 1e-4)
        assertEquals(CinemaHall.RAKE.toDouble(), rows.getDouble("rake"), 1e-4)
        val seats = o.getJSONArray("seatRows")
        assertEquals(CinemaHall.SEAT_ROWS.toList(), (0 until seats.length()).map { seats.getInt(it) })
        assertEquals(CinemaHall.SEAT_TOP.toDouble(), o.getDouble("seatTop"), 1e-4)
        assertEquals(CinemaHall.SEAT_TOP_BEHIND_EYE.toDouble(), o.getDouble("seatTopBehindEye"), 1e-4)
        val parapet = o.getJSONObject("parapet")
        assertEquals(CinemaHall.PARAPET_Z.toDouble(), parapet.getDouble("z"), 1e-4)
        assertEquals(CinemaHall.PARAPET_TOP.toDouble(), parapet.getDouble("top"), 1e-4)
        assertEquals(CinemaHall.PARAPET_DEPTH.toDouble(), parapet.getDouble("depth"), 1e-4)
        val curtain = o.getJSONObject("curtain")
        assertEquals(CinemaHall.CURTAIN_RISE.toDouble(), curtain.getDouble("rise"), 1e-4)
        assertEquals(CinemaHall.CURTAIN_BOTTOM.toDouble(), curtain.getDouble("bottom"), 1e-4)
        assertEquals(CinemaHall.CURTAIN_TOP.toDouble(), curtain.getDouble("top"), 1e-4)
        assertEquals(CinemaHall.CURTAIN_FRONT.toDouble(), curtain.getDouble("front"), 1e-4)
        assertEquals(CinemaHall.CURTAIN_HALF_W.toDouble(), curtain.getDouble("halfWidth"), 1e-4)
        assertEquals(CinemaHall.VALANCE_BOTTOM.toDouble(), o.getJSONObject("hall").getDouble("valanceBottom"), 1e-4)
        // Every material is one the headset knows how to light.
        val names = o.getJSONArray("materials").let { a -> (0 until a.length()).map { a.getString(it) } }
        assertTrue(names.any { it == "walls@L/baked" } && names.any { it == "walls@R/baked" } && names.any { it == "hall/baked" })
        assertTrue(names.any { BakedLight.kindOf(it) == BakedLight.Kind.LAMP } && names.any { BakedLight.kindOf(it) == BakedLight.Kind.GLOW })
        names.filter { BakedLight.kindOf(it) == BakedLight.Kind.SURFACE }.forEach { assertTrue("$it is baked", it.endsWith("/baked")) }
    }

    /** The model itself: a glTF binary whose baked materials are plain pictures (made unlit on loading), the left wall on your left. */
    @Test fun theModelIsDrawnAsBaked() {
        val glb = File("src/main/assets/environments/cinema.glb")
        if (!glb.exists()) return
        val gltf = Glb.read(glb)
        val materials = gltf.getJSONArray("materials")
        for (i in 0 until materials.length()) {
            val m = materials.getJSONObject(i)
            val name = m.getString("name")
            // Not marked unlit in the file: the Quest's loader drew those white. The app makes them unlit once loaded.
            assertTrue("$name plain in the file", m.optJSONObject("extensions")?.has("KHR_materials_unlit") != true)
            if (name.endsWith("/baked")) assertTrue("$name shows its bake", m.getJSONObject("pbrMetallicRoughness").has("baseColorTexture"))
        }
        // Each side's walls on that side (x > 0 is your left).
        val meshes = gltf.getJSONArray("meshes")
        val accessors = gltf.getJSONArray("accessors")
        for (i in 0 until meshes.length()) {
            val prims = meshes.getJSONObject(i).getJSONArray("primitives")
            for (j in 0 until prims.length()) {
                val p = prims.getJSONObject(j)
                val name = materials.getJSONObject(p.getInt("material")).getString("name")
                val pos = accessors.getJSONObject(p.getJSONObject("attributes").getInt("POSITION"))
                val min = pos.getJSONArray("min"); val max = pos.getJSONArray("max")
                if (name.startsWith("walls@L")) assertTrue("the left wall at x ${min.getDouble(0)}", min.getDouble(0) > 5)
                if (name.startsWith("walls@R")) assertTrue("the right wall at x ${max.getDouble(0)}", max.getDouble(0) < -5)
                if (name == "hall/baked") {
                    // In front of you (+z) to the screen at z 0, and the hall behind.
                    assertTrue(max.getDouble(2) in 0.0..1.0 && min.getDouble(2) < -20)
                    assertTrue(max.getDouble(1) > CinemaHall.SCREEN_BOTTOM + CinemaHall.SCREEN_H)
                }
            }
        }
    }
}

/** The JSON part of a glTF binary. */
object Glb {
    fun read(file: File): org.json.JSONObject {
        val b = java.nio.ByteBuffer.wrap(file.readBytes()).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        check(b.getInt(0) == 0x46546C67) { "not a glb" }
        val length = b.getInt(12)
        check(b.getInt(16) == 0x4E4F534A) { "no JSON chunk" }
        return org.json.JSONObject(String(file.readBytes(), 20, length, Charsets.UTF_8))
    }
}
