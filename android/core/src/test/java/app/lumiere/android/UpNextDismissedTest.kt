package app.lumiere.android

import app.lumiere.android.UpNextDismissed.Companion.CONTINUE
import app.lumiere.android.UpNextDismissed.Companion.NEXT_UP
import app.lumiere.android.UpNextDismissed.Companion.UP_NEXT
import app.lumiere.android.api.Item
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A show taken off Up Next stays off, across a restart, until you next play it. */
class UpNextDismissedTest {
    private var disk: String? = null
    private fun open() = UpNextDismissed("me", disk) { disk = it }

    private val film = Item("f1", "Arrival", "Movie")
    private fun episode(id: String, show: String, at: Long = 0) = Item(id, "Episode", "Episode", seriesId = show, positionTicks = at)

    @Test fun aShowTakenOffIsStillOffAfterARestart() {
        open().dismiss("severance")
        val again = open()
        assertTrue("severance" in again)
        assertEquals(listOf("severance"), again.shows)
    }

    @Test fun playingItBringsItBackForGood() {
        val list = open()
        list.dismiss("severance")
        assertTrue(list.restore("severance"))
        assertFalse("severance" in open())
        assertFalse("nothing to bring back", list.restore("severance"))
        assertFalse(list.restore(null))
    }

    @Test fun anEpisodeGoesWithItsShowAndFilmsStay() {
        val list = open()
        list.dismiss("severance")
        val row = listOf(episode("e5", "severance"), film, episode("x2", "slow-horses"))
        assertEquals(listOf(film, row[2]), list.filter(row))
    }

    @Test fun nothingSavedOrADamagedLineLoadsEmpty() {
        assertTrue(UpNextDismissed("me", null) {}.shows.isEmpty())
        assertTrue(UpNextDismissed("me", "") {}.shows.isEmpty())
        assertEquals(listOf("a", "b"), UpNextDismissed.decode(" a,,b, a ,"))
    }

    @Test fun newestFirstAndNeverMoreThanTheCap() {
        val list = open()
        repeat(UpNextDismissed.MAX + 5) { list.dismiss("s$it") }
        list.dismiss("s50")
        assertEquals(UpNextDismissed.MAX, open().shows.size)
        assertEquals("s50", open().shows.first())
        assertEquals(1, open().shows.count { it == "s50" })
    }

    @Test fun continueWatchingOnlyForgetsWhereYouWere() {
        val r = UpNextDismissed.removal(CONTINUE, episode("e5", "severance", at = 9), emptyList())
        assertEquals(UpNextDismissed.Removal(unlist = false, hide = true, dismiss = null), r)
    }

    @Test fun nextUpOnlyKeepsTheShowOff() {
        val r = UpNextDismissed.removal(NEXT_UP, episode("e5", "severance", at = 9), listOf("e5"))
        assertEquals(UpNextDismissed.Removal(unlist = false, hide = false, dismiss = "severance"), r)
    }

    @Test fun theOneUpNextRowUndoesEverythingThatWouldBringItBack() {
        assertEquals(UpNextDismissed.Removal(unlist = false, hide = true, dismiss = "severance"),
            UpNextDismissed.removal(UP_NEXT, episode("e5", "severance", at = 9), emptyList()))
        // A film you added yourself: off the list, with no show to keep off.
        val r = UpNextDismissed.removal(UP_NEXT, film, listOf("f1"))
        assertTrue(r.unlist); assertFalse(r.hide); assertNull(r.dismiss)
        // A show you added yourself is also kept off, or its next episode would take its place.
        assertEquals("sh", UpNextDismissed.removal(UP_NEXT, Item("sh", "Severance", "Series"), listOf("sh")).dismiss)
    }
}
