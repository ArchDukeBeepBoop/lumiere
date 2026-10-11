package app.lumiere.android

import app.lumiere.android.api.Item
import app.lumiere.android.api.Segment
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.ui.PreviewChoice
import app.lumiere.android.ui.PreviewClip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the banner plays: a trailer first, else the opening, and never past a tenth of the way in. */
class BannerPreviewTest {
    private fun film(minutes: Long, id: String = "f") =
        Item(id, "Arrival", "Movie", runtimeTicks = minutes * 60 * TICKS_PER_SECOND, mediaSourceId = "${id}s")
    private fun episode(minutes: Long) = Item("e", "Pilot", "Episode", seriesId = "show", runtimeTicks = minutes * 60 * TICKS_PER_SECOND)
    private fun trailer(id: String) = Item(id, "Trailer", "Trailer", mediaSourceId = "${id}s", runtimeTicks = 150 * TICKS_PER_SECOND)

    @Test fun theFirstTrailerPlaysFromItsStartAndWhole() {
        assertEquals(PreviewClip("t1", "t1s", 0, null), PreviewChoice.trailer(listOf(trailer("t1"), trailer("t2"))))
        assertNull(PreviewChoice.trailer(emptyList()))
    }

    @Test fun anEpisodeOrShowAsksForTheShowsTrailer() {
        assertEquals("show", PreviewChoice.trailerOwner(episode(45)))
        assertEquals("show", PreviewChoice.trailerOwner(Item("show", "Severance", "Series")))
        assertEquals("f", PreviewChoice.trailerOwner(film(120)))
        // A collection or a folder has nothing to play.
        assertNull(PreviewChoice.trailerOwner(Item("c", "Alien Collection", "BoxSet")))
        assertNull(PreviewChoice.trailerOwner(Item("s", "Season 1", "Season")))
    }

    @Test fun aTrailerComesBeforeTheOpening() {
        val clip = PreviewChoice.trailer(listOf(trailer("t1"))) ?: PreviewChoice.opening(film(120), emptyList())
        assertEquals("t1", clip!!.itemId)
    }

    @Test fun withNoIntroMarkTheOpeningStartsNinetySecondsIn() {
        assertEquals(PreviewClip("f", "fs", 90_000, 180_000), PreviewChoice.opening(film(120), emptyList()))
    }

    @Test fun theOpeningStartsWhereTheIntroEnds() {
        val clip = PreviewChoice.opening(episode(45), listOf(Segment("Intro", 30.0, 95.0)))!!
        assertEquals(95_000L, clip.startMs)
        assertEquals(185_000L, clip.endMs)
    }

    @Test fun aRecapIsSteppedPastAndTheNextMarkEndsTheStretch() {
        // A recap of earlier episodes over the 90-second mark, then the intro.
        val clip = PreviewChoice.opening(episode(45), listOf(Segment("Recap", 0.0, 120.0), Segment("Intro", 160.0, 200.0)))!!
        // The intro's end, not the recap, is where it starts.
        assertEquals(200_000L, clip.startMs)
        val noIntro = PreviewChoice.opening(episode(45), listOf(Segment("Recap", 0.0, 120.0), Segment("Outro", 150.0, 170.0)))!!
        assertEquals(120_000L, noIntro.startMs)
        assertEquals(150_000L, noIntro.endMs)
    }

    @Test fun neverPastATenthOfTheRuntime() {
        // A 22-minute episode: a tenth is 132 seconds.
        assertEquals(132_000L, PreviewChoice.opening(episode(22), emptyList())!!.endMs)
        // An intro that ends past the tenth: the 90-second mark instead, up to where the intro begins.
        assertEquals(PreviewClip("e", null, 90_000, 120_000), PreviewChoice.opening(episode(22), listOf(Segment("Intro", 120.0, 150.0))))
        // Both inside the intro or past the tenth: no stretch is safe, so nothing plays.
        assertNull(PreviewChoice.opening(episode(22), listOf(Segment("Intro", 60.0, 140.0))))
        // A short film has no safe stretch at all.
        assertNull(PreviewChoice.opening(film(16), emptyList()))
        for (minutes in 1L..240L) for (intro in listOf(null, 20.0, 75.0, 300.0, 1_000.0)) {
            val clip = PreviewChoice.opening(film(minutes), listOfNotNull(intro?.let { Segment("Intro", 5.0, it) })) ?: continue
            assertTrue("$minutes min, intro to $intro", clip.endMs!! <= minutes * 60_000 / 10)
            assertTrue(clip.endMs!! - clip.startMs >= PreviewChoice.SHORTEST_MS)
        }
    }

    @Test fun aShowOrAnUnknownLengthHasNoOpening() {
        assertNull(PreviewChoice.opening(Item("show", "Severance", "Series", runtimeTicks = 50 * 60 * TICKS_PER_SECOND), emptyList()))
        assertNull(PreviewChoice.opening(Item("f", "Arrival", "Movie"), emptyList()))
    }
}
