package app.lumiere.android

import app.lumiere.android.api.Item
import app.lumiere.android.api.StereoLayout
import app.lumiere.android.api.StereoLayout.MONO
import app.lumiere.android.api.StereoLayout.SIDE_BY_SIDE
import app.lumiere.android.api.StereoLayout.TOP_BOTTOM
import app.lumiere.android.api.eyeAspect
import app.lumiere.android.api.stereoLayoutIn
import app.lumiere.android.api.stereoLayoutOf
import org.junit.Assert.assertEquals
import org.junit.Test

/** Cases after DeadEasy Player's ProjectionModeDetectorTest (MIT), and Lumiere's own. */
class StereoTest {
    private fun layout(name: String): StereoLayout = stereoLayoutIn(name) ?: MONO

    @Test fun tagsBetweenAnyDelimiter() {
        listOf("movie.SBS.mkv", "movie.HSBS.mkv", "Movie.3d.SbS.mkv", "Avatar.3D.hsbs.1080p.mkv",
            "movie_sbs_1080p.mkv", "movie-sbs-vr.mkv", "Movie HSBS 2024.mkv", "SBS.mp4", "movie_sbs",
            "Avatar (2009) [Half-SBS]", "Gravity 3D Half SBS").forEach { assertEquals(it, SIDE_BY_SIDE, layout(it)) }
        listOf("movie.OU.mkv", "movie.HOU.mkv", "Documentary.Ou.mp4", "clip_ou_4k.mp4", "film-ou-3d.mkv",
            "Movie HOU VR.mkv", "OU.mp4", "movie-ou", "Hugo (2011) [TAB]").forEach { assertEquals(it, TOP_BOTTOM, layout(it)) }
    }

    @Test fun ordinaryWordsStayFlat() {
        listOf("BigBuckBunny.mp4", "Inception.2010.1080p.mkv", "output.mp4", "route.mp4", "continuous.mkv",
            "asbestos.mp4", "south_park_s01e01.mkv", "loudness_audio.mp4", "Où est la maison", "Table Manners",
            "You", "Jabsbsr").forEach { assertEquals(it, MONO, layout(it)) }
    }

    @Test fun aKnown3DTitleWithoutATagIsSideBySide() {
        assertEquals(SIDE_BY_SIDE, stereoLayoutOf(Item("1", "Avatar", "Movie"), known3D = true))
        assertEquals(TOP_BOTTOM, stereoLayoutOf(Item("1", "Avatar HOU", "Movie"), known3D = true))
        assertEquals(MONO, stereoLayoutOf(Item("1", "Avatar", "Movie"), known3D = false))
    }

    @Test fun eachEyeSeesItsOwnShape() {
        assertEquals(16f / 9, eyeAspect(SIDE_BY_SIDE, 3840, 1080), 0.01f)
        assertEquals(16f / 9, eyeAspect(SIDE_BY_SIDE, 1920, 1080), 0.01f)
        assertEquals(16f / 9, eyeAspect(TOP_BOTTOM, 1920, 2160), 0.01f)
        assertEquals(16f / 9, eyeAspect(TOP_BOTTOM, 1920, 1080), 0.01f)
        assertEquals(2.39f, eyeAspect(MONO, 1920, 803), 0.01f)
    }
}
