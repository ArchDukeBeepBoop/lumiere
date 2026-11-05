package app.lumiere.android.tv.browse

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FakeCatalogTest {
    private val rows = runBlocking { FakeCatalog.rows() }

    @Test fun sixRowsOfFifteen() {
        assertEquals(6, rows.size)
        rows.forEach { assertEquals("${it.title} holds fifteen", 15, it.items.size) }
    }

    @Test fun mixesCardKindsAndRowZeroIsLandscape() {
        assertEquals(CardType.Landscape, rows.first().cardType)
        assertEquals(CardType.entries.toSet(), rows.map { it.cardType }.toSet())
    }

    @Test fun keysAreStableAndUnique() {
        val ids = rows.flatMap { r -> r.items.map { it.id } }
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(rows.size, rows.map { it.id }.toSet().size)
    }

    @Test fun continueWatchingShowsProgressAndTitles() {
        val cw = rows.first { it.id == "continue" }
        assertTrue(cw.alwaysShowTitle)
        assertTrue(cw.items.all { it.progress != null && it.progress!! in 0f..1f })
    }

    @Test fun artIsLocal() = assertTrue(rows.flatMap { it.items }.all { it.cardArt == null && it.backdrop == null })
}
