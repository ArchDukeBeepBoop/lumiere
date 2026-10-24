package app.lumiere.android

import app.lumiere.android.api.Item
import app.lumiere.android.cache.OfflineShelves
import org.junit.Assert.assertEquals
import org.junit.Test

class OfflineShelvesTest {
    private fun ep(id: String, show: String, s: Int, e: Int, played: Boolean = false, at: Long = 0) =
        Item(id = id, name = id, type = "Episode", seriesId = show, parentIndexNumber = s, indexNumber = e,
            played = played, positionTicks = at)

    @Test fun upNextIsTheEpisodeAfterTheFurthestWatched() {
        val items = listOf(ep("a3", "A", 1, 3), ep("a1", "A", 1, 1, played = true), ep("a2", "A", 1, 2, played = true), ep("a4", "A", 1, 4))
        assertEquals(listOf("a3"), OfflineShelves.upNext(items) { 0 }.map { it.id })
    }

    @Test fun aHalfWatchedEpisodeBelongsToResumeNotUpNext() {
        val items = listOf(ep("a1", "A", 1, 1, played = true), ep("a2", "A", 1, 2, at = 50))
        assertEquals(emptyList<String>(), OfflineShelves.upNext(items) { 0 }.map { it.id })
        assertEquals(listOf("a2"), OfflineShelves.resume(items) { 0 }.map { it.id })
    }

    @Test fun showsWatchedLatelyComeFirstAndSeasonsCarryOn() {
        val items = listOf(ep("a1", "A", 1, 9, played = true), ep("a2", "A", 2, 1),
            ep("b1", "B", 1, 1, played = true), ep("b2", "B", 1, 2))
        val last = mapOf("a1" to 10L, "b1" to 20L)
        assertEquals(listOf("b2", "a2"), OfflineShelves.upNext(items) { last[it] ?: 0 }.map { it.id })
    }
}
