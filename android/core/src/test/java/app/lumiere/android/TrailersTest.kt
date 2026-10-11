package app.lumiere.android

import app.lumiere.android.api.parseTrailers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrailersTest {
    @Test fun localTrailersAreABareArrayInTheServersOrder() {
        val trailers = parseTrailers("""[
            {"Id":"t1","Name":"Teaser","Type":"Trailer","RunTimeTicks":1500000000,"LocationType":"FileSystem",
             "MediaSources":[{"Id":"t1s","Protocol":"File","Path":"/films/Arrival (2016)/trailers/teaser.mkv"}]},
            {"Id":"t2","Name":"Trailer 2","Type":"Video","ExtraType":"Trailer",
             "MediaSources":[{"Id":"t2","Protocol":"File","Path":"/films/Arrival (2016)/Arrival-trailer.mp4"}]}]""")
        assertEquals(listOf("t1", "t2"), trailers.map { it.id })
        assertEquals("t1s", trailers.first().mediaSourceId)
        assertEquals(1_500_000_000L, trailers.first().runtimeTicks)
    }

    @Test fun youTubeAndOtherWebTrailersAreLeftOut() {
        val trailers = parseTrailers("""[
            {"Id":"yt","Name":"Official Trailer","Type":"Trailer","Path":"https://www.youtube.com/watch?v=tFMo3UJ4B4g"},
            {"Id":"remote","Name":"Trailer","Type":"Trailer","LocationType":"Remote"},
            {"Id":"http","Name":"Trailer","Type":"Trailer","MediaSources":[{"Id":"http","Protocol":"Http","Path":"/x.mp4"}]},
            {"Id":"kodi","Name":"Trailer","Type":"Trailer","Path":"plugin://plugin.video.youtube/play/?video_id=abc"},
            {"Id":"local","Name":"Trailer","Type":"Trailer","MediaSources":[{"Id":"local","Protocol":"File","Path":"/films/youtube rips/trailer.mkv"}]}]""")
        // A local file is kept even when its folder happens to be named after YouTube.
        assertEquals(listOf("local"), trailers.map { it.id })
    }

    @Test fun anEnvelopeOrNothingAtAll() {
        assertEquals(listOf("a"), parseTrailers("""{"Items":[{"Id":"a","Name":"A","Type":"Trailer"}]}""").map { it.id })
        assertTrue(parseTrailers("[]").isEmpty())
        assertTrue(parseTrailers("""{"TotalRecordCount":0}""").isEmpty())
    }
}
