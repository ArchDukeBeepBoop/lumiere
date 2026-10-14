package app.lumiere.android.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecondSubtitlesTest {
    private val vtt = """WEBVTT

NOTE a note

1
00:00:01.000 --> 00:00:03.500 align:start position:10%
<i>Hello</i> there

00:04.000 --> 00:06.000
Two lines
here &amp; now
"""

    @Test fun webVttIsReadWithoutItsStyling() {
        val cues = SecondSubtitles.parse(vtt)
        assertEquals(2, cues.size)
        assertEquals(SecondSubtitles.Cue(1000, 3500, "Hello there"), cues[0])
        assertEquals("Two lines\nhere & now", cues[1].text)
        assertEquals(4000, cues[1].startMs)
    }

    @Test fun subRipToo() {
        val srt = "1\r\n00:01:02,250 --> 00:01:04,000\r\n{\\an8}Up here\r\n\r\n2\r\n01:00:00,000 --> 01:00:01,000\r\nLate\r\n"
        val cues = SecondSubtitles.parse(srt)
        assertEquals(listOf(62250L, 3600000L), cues.map { it.startMs })
        assertEquals("Up here", cues[0].text)
    }

    @Test fun whatShowsAtATime() {
        val cues = SecondSubtitles.parse(vtt)
        assertNull(SecondSubtitles.at(cues, 500))
        assertEquals("Hello there", SecondSubtitles.at(cues, 2000))
        assertNull(SecondSubtitles.at(cues, 3700))
        assertEquals("Two lines\nhere & now", SecondSubtitles.at(cues, 5999))
        assertNull(SecondSubtitles.at(cues, 6000))
        // Overlapping lines both show.
        val both = listOf(SecondSubtitles.Cue(0, 5000, "A"), SecondSubtitles.Cue(1000, 2000, "B"))
        assertEquals("A\nB", SecondSubtitles.at(both, 1500))
    }

    @Test fun picturesHaveNoText() {
        assertFalse(SecondSubtitles.readable("PGSSUB"))
        assertTrue(SecondSubtitles.readable("subrip"))
        assertTrue(SecondSubtitles.readable(null))
    }

    @Test fun streamsAreNamedForPeople() {
        assertEquals("French", SecondSubtitles.label("fre", null))
        assertEquals("English · SDH", SecondSubtitles.label("eng", "SDH"))
        assertEquals("Unnamed", SecondSubtitles.label("und", ""))
    }
}
