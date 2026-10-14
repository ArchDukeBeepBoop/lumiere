package app.lumiere.android

import app.lumiere.android.api.Projection
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.projectionIn
import app.lumiere.android.api.surroundEyes
import org.junit.Assert.assertEquals
import org.junit.Test

class ProjectionTest {
    private fun of(vararg names: String, w: Int = 0, h: Int = 0) = projectionIn(names.toList(), w, h)

    @Test fun explicitTagsSaySoOutright() {
        assertEquals(Projection.HALF_SPHERE, of("Lisbon Walk VR180"))
        assertEquals(Projection.HALF_SPHERE, of("Concert", "/vr/Concert_180x180_LR.mp4"))
        assertEquals(Projection.SPHERE, of("Reef (360°)"))
        assertEquals(Projection.SPHERE, of("Northern Lights", "/vr/lights.vr360.mp4"))
    }

    @Test fun aBareNumberNeedsAnEyeTagOrAnEquirectPicture() {
        assertEquals(Projection.SPHERE, of("Beach", "/vr/Beach_360_TB.mp4"))
        assertEquals(Projection.SPHERE, of("Beach 360", w = 3840, h = 1920))
        assertEquals(Projection.HALF_SPHERE, of("Cliffs_180", w = 5760, h = 2880))
    }

    @Test fun filmsThatOnlyHaveTheNumberInTheirTitleStayFlat() {
        assertEquals(Projection.FLAT, of("360", "/Movies/360 (2011)/360.mkv", w = 1920, h = 816))
        assertEquals(Projection.FLAT, of("180 Days", w = 1920, h = 1080))
        assertEquals(Projection.FLAT, of("Movie 1080p 2160p 1800", w = 3840, h = 2160))
        assertEquals(Projection.FLAT, of("Something 360p"))
    }

    @Test fun theEyesComeFromTheTagThenTheShape() {
        assertEquals(StereoLayout.TOP_BOTTOM, surroundEyes(listOf("Beach_360_TB"), Projection.SPHERE, 3840, 3840))
        assertEquals(StereoLayout.SIDE_BY_SIDE, surroundEyes(listOf("Cliffs_180_LR"), Projection.HALF_SPHERE, 5760, 2880))
        assertEquals(StereoLayout.MONO, surroundEyes(listOf("Reef 360"), Projection.SPHERE, 3840, 1920))
        assertEquals(StereoLayout.TOP_BOTTOM, surroundEyes(listOf("Reef 360"), Projection.SPHERE, 4096, 4096))
        assertEquals(StereoLayout.SIDE_BY_SIDE, surroundEyes(listOf("Walk VR180"), Projection.HALF_SPHERE, 5760, 2880))
        assertEquals(StereoLayout.MONO, surroundEyes(listOf("Walk VR180 mono"), Projection.HALF_SPHERE, 4096, 4096))
    }
}
