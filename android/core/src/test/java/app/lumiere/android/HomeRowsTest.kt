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

    @Test fun aCompactHomeKeepsItsSixAndAddsMyList() {
        val rows = Prefs.homeRows(Prefs.TV_ROWS, emptySet(), compact = true)
        assertEquals(listOf("continue", "nextup", "finish", "mylist", "series", "libraries", "recent"), rows)
        assertEquals(Prefs.homeRows(before, emptySet(), compact = true), rows - "mylist")
    }

    @Test fun aCompactHomeLeavesMyListOutWhenMovedBelowTheSix() {
        val rows = Prefs.homeRows(before + "mylist", emptySet(), compact = true)
        assertEquals(before.take(6), rows)
        assertEquals(listOf("mylist"), Prefs.homeRows(listOf("mylist", "genres"), setOf("genres"), compact = true))
    }

    @Test fun rowsSwitchedOffAreLeftOut() {
        val rows = Prefs.homeRows(Prefs.TV_ROWS, setOf("mylist"), compact = false)
        assertEquals(Prefs.TV_ROWS - "mylist", rows)
    }
}
