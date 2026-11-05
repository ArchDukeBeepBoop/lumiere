package app.lumiere.android

import app.lumiere.android.api.Item
import app.lumiere.android.api.inWatchOrder
import org.junit.Assert.assertEquals
import org.junit.Test

class WatchOrderTest {
    private fun film(id: String, year: Int) = Item(id = id, name = id, type = "Movie", year = year)
    private val films = listOf(film("new", 2019), film("old", 2001), film("mid", 2010))

    @Test fun theMacsOrderWinsOverYears() =
        assertEquals(listOf("mid", "new", "old"), inWatchOrder(films, listOf("mid", "new", "old")).map { it.id })

    @Test fun titlesTheOrderDoesntListComeAfterItOldestFirst() =
        assertEquals(listOf("new", "old", "mid"), inWatchOrder(films, listOf("new", "gone")).map { it.id })

    @Test fun withNoOrderItsByYear() =
        assertEquals(listOf("old", "mid", "new"), inWatchOrder(films, null).map { it.id })
}
