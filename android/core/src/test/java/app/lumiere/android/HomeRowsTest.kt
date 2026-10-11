package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** My List takes its place after Up Next, for a new TV and one with a saved order alike. */
class HomeRowsTest {
    private val before = Prefs.TV_ROWS - "mylist"

    @Test fun aSavedOrderGetsMyListAfterUpNextNotAtTheEnd() {
        val order = Prefs.withNewRows(before)
        assertEquals(order.indexOf("finish") + 1, order.indexOf("mylist"))
        assertEquals(Prefs.TV_ROWS, order)
    }

    @Test fun aRowMovedByHandKeepsItsPlace() {
        val moved = listOf("libraries", "continue", "nextup", "recent", "finish") + before.filter { it !in setOf("libraries", "continue", "nextup", "recent", "finish") }
        val order = Prefs.withNewRows(moved)
        assertEquals(listOf("libraries", "continue", "nextup", "recent", "finish", "mylist"), order.take(6))
        assertEquals(Prefs.TV_ROWS.toSet(), order.toSet())
    }

    @Test fun nothingSavedIsTheDefaultAndAnUnknownRowIsKept() {
        assertEquals(Prefs.TV_ROWS, Prefs.withNewRows(emptyList()))
        assertTrue("future" in Prefs.withNewRows(listOf("future") + Prefs.TV_ROWS))
        assertEquals(Prefs.TV_ROWS, Prefs.withNewRows(Prefs.TV_ROWS))
    }

    @Test fun aCompactHomeStillReachesRecentlyAdded() {
        val rows = Prefs.homeRows(Prefs.TV_ROWS, emptySet(), merged = true, compact = true)
        assertEquals(listOf("continue", "mylist", "series", "libraries", "recent", "because"), rows)
    }

    @Test fun rowsSwitchedOffAreLeftOut() {
        val rows = Prefs.homeRows(Prefs.TV_ROWS, setOf("mylist"), merged = false, compact = false)
        assertEquals(Prefs.TV_ROWS - "mylist", rows)
    }
}
