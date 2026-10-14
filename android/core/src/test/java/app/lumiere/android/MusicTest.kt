package app.lumiere.android

import app.lumiere.android.api.currentLyric
import app.lumiere.android.api.parseItems
import app.lumiere.android.api.parseLyrics
import app.lumiere.android.api.toLrc
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MusicTest {
    @Test fun syncedLyricsFollowTheSong() {
        val lines = parseLyrics("""{"Lyrics":[{"Text":"It's just me","Start":94300000},{"Text":"Nothin' to lose","Start":138400000}]}""")!!
        assertNull(currentLyric(lines, 5.0))
        assertEquals(0, currentLyric(lines, 10.0))
        assertEquals(1, currentLyric(lines, 20.0))
        assertEquals("[00:09.43]It's just me\n[00:13.84]Nothin' to lose", toLrc(lines))
    }

    @Test fun plainLyricsHaveNoCurrentLine() {
        val lines = parseLyrics("""{"Lyrics":[{"Text":"First"},{"Text":"Second"}]}""")!!
        assertNull(currentLyric(lines, 100.0))
        assertEquals("First\nSecond", toLrc(lines))
    }

    @Test fun trackCarriesItsAlbumAndLibrary() {
        val track = parseItems("""{"Items":[{"Id":"t","Name":"Changes","Type":"Audio","ParentId":"al","Album":"Greatest Hits",
            "AlbumArtist":"2Pac","Artists":["2Pac","Talent"],"TopParentId":"music","UserData":{"IsFavorite":true}}]}""").single()
        assertEquals("al", track.albumId)
        assertEquals("music", track.libraryId)
        assertEquals(listOf("2Pac", "Talent"), track.artists)
        assertEquals(true, track.favorite)
    }
}

class DiscoveryTest {
    @Test fun scansTheRestOfTheHomeNetwork() {
        val hosts = app.lumiere.android.api.Discovery.hostsAround(byteArrayOf(192.toByte(), 168.toByte(), 50, 28))
        assertEquals(253, hosts.size)
        assertEquals("192.168.50.1", hosts.first())
        assertEquals(false, "192.168.50.28" in hosts)
    }
}
