package app.lumiere.android.spatial

import app.lumiere.android.spatial.StereoDetect.Format
import org.junit.Assert.assertEquals
import org.junit.Test

/** First drafted by Hermes (Solar Mini 4), corrected and completed here. */
class StereoDetectTest {
    private fun of(name: String, w: Int = 1920, h: Int = 1080) = StereoDetect.of(name, w, h)

    @Test fun sideBySideTags() {
        listOf("Avatar 3D SBS", "Avatar.HSBS.1080p", "Avatar [3D-SBS]", "Avatar Half-SBS", "Avatar LR")
            .forEach { assertEquals(it, Format.SBS, of(it)) }
    }

    @Test fun overUnderTags() {
        listOf("Gravity OU", "Gravity.HOU", "Gravity TB", "Gravity (TAB)", "Gravity Half-OU")
            .forEach { assertEquals(it, Format.OU, of(it)) }
    }

    @Test fun vr180WithSideBySideIs180() = assertEquals(Format.VR180_SBS, of("Concert VR180 SBS"))
    @Test fun vr180AloneIs180Too() = assertEquals(Format.VR180_SBS, of("Concert 180"))
    @Test fun threeSixtyOverUnder() = assertEquals(Format.VR360_OU, of("Dive 360 TB"))
    @Test fun threeSixtyAloneIsMono() = assertEquals(Format.VR360_MONO, of("City Walk 360"))

    @Test fun lettersInsideWordsStayFlat() {
        listOf("Absolution", "Tobacco Road", "Collateral", "Lord of War", "Moulin Rouge")
            .forEach { assertEquals(it, Format.FLAT, of(it)) }
    }

    @Test fun twoFramesSideBySideByShape() = assertEquals(Format.SBS, of("Untitled", 3840, 1080))
    @Test fun aTwoToOne4kPictureIs360() = assertEquals(Format.VR360_MONO, of("Untitled", 3840, 1920))
    @Test fun aSmallTwoToOneIsJustWide() = assertEquals(Format.FLAT, of("Untitled", 1920, 960))
    @Test fun aScopeFilmIsFlat() = assertEquals(Format.FLAT, of("Untitled", 1920, 804))
    @Test fun tagsWinOverShape() = assertEquals(Format.OU, of("Gravity OU", 3840, 1080))

    @Test fun eachEyesShape() {
        assertEquals(16f / 9f, StereoDetect.eyeAspect(Format.SBS, 3840, 1080), 0.01f)
        assertEquals(16f / 9f, StereoDetect.eyeAspect(Format.SBS, 1920, 1080), 0.01f)
        assertEquals(16f / 9f, StereoDetect.eyeAspect(Format.OU, 1920, 2160), 0.01f)
        assertEquals(16f / 9f, StereoDetect.eyeAspect(Format.OU, 1920, 1080), 0.01f)
    }

    @Test fun aFilmIn2DKeepsOneEyesShape() {
        assertEquals(16f / 9f, StereoDetect.eyeAspect(Format.SBS_2D, 3840, 1080), 0.01f)
        assertEquals(false, Format.SBS_2D.stereo)
    }
}
