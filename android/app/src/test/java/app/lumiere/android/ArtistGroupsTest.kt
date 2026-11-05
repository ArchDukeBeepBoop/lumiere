package app.lumiere.android

import app.lumiere.android.api.Item
import app.lumiere.android.music.ArtistGroups
import org.junit.Assert.assertEquals
import org.junit.Test

class ArtistGroupsTest {
    private fun a(id: String, name: String, tag: String? = null, album: String? = null) = Item(id = id, name = name, type = "MusicArtist", primaryTag = tag, albumId = album)

    @Test fun guestsAreFoldedUnderThePrimaryArtist() {
        val known = setOf("kanye west", "katy perry", "birdman")
        assertEquals("Katy Perry", ArtistGroups.primary("Katy Perry feat. Juicy J", known))
        assertEquals("Classified", ArtistGroups.primary("Classified feat. B.o.B", known))
        assertEquals("K City", ArtistGroups.primary("K City Feat.J Watts", known))
        assertEquals("D'banj", ArtistGroups.primary("D'banj (feat. Snoop Dogg)", known))
        assertEquals("Kanye West", ArtistGroups.primary("Kanye West & JAY-Z", known))
        assertEquals("Birdman", ArtistGroups.primary("Birdman, Fabolous, Jim Jones & Sean Paul", known))
        assertEquals("Franz Schubert", ArtistGroups.primary("Franz Schubert; Karl Böhm, Berlin Philharmonic Orchestra", known))
        assertEquals("Kagrra", ArtistGroups.primary("Kagrra,", known))
    }

    @Test fun aBandsOwnNameStaysWhole() {
        val known = setOf("bob marley & the wailers", "chase & status", "aly & aj")
        assertEquals("Bob Marley & The Wailers", ArtistGroups.primary("Bob Marley & The Wailers", known))
        assertEquals("Chase & Status", ArtistGroups.primary("Chase & Status", known))
        assertEquals("Krewella & Yellow Claw", ArtistGroups.primary("Krewella & Yellow Claw feat. Vava", known))
    }

    @Test fun oneCardPerArtistWithTheirOwnPhotoFirst() {
        val groups = ArtistGroups.group(listOf(
            a("1", "Lil Wayne feat. Eminem", tag = "x"), a("2", "Lil Wayne", tag = "own"),
            a("3", "lil wayne & DJ Drama"), a("4", "Birdman feat. Rick Ross", album = "al"),
            a("5", "Aly & AJ"),
        ))
        assertEquals(listOf("Aly & AJ", "Birdman", "Lil Wayne"), groups.map { it.item.name })
        val wayne = groups.last()
        assertEquals(listOf("2", "1", "3"), wayne.ids)
        assertEquals("2" to "own", wayne.imageId to wayne.imageTag)
        // No photo anywhere: the newest album's cover.
        assertEquals("al" to null, groups[1].imageId to groups[1].imageTag)
    }
}
