package app.lumiere.android.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchKeysTest {
    @Test fun theKeyboardFitsInTheMiddleOfATv() {
        // The old single line ran to about 1900 dp, off both edges of a 1920 dp-wide screen.
        assertTrue("${SearchKeys.widthDp} dp", SearchKeys.widthDp <= 1100)
    }

    @Test fun everyLetterAndDigitHasAKeyOnce() {
        val keys = SearchKeys.rows.flatten()
        assertEquals(keys.size, keys.toSet().size)
        ('a'..'z').forEach { assertTrue("$it", it.toString() in keys) }
        ('0'..'9').forEach { assertTrue("$it", it.toString() in keys) }
        listOf(SearchKeys.SPACE, SearchKeys.BACK, SearchKeys.CLEAR).forEach { assertTrue(it, it in keys) }
    }

    @Test fun eachKeyIsWideEnoughToHitWithARemote() {
        SearchKeys.rows.forEach { row ->
            val perSpan = (SearchKeys.widthDp - (row.size - 1) * SearchKeys.GAP_DP) / row.sumOf { SearchKeys.span(it).toDouble() }
            assertTrue("$perSpan dp", perSpan >= 52)
        }
    }

    @Test fun theKeysTypeAsTheySay() {
        assertEquals("dun", SearchKeys.press("du", "n"))
        assertEquals("the ", SearchKeys.press("the", SearchKeys.SPACE))
        assertEquals("du", SearchKeys.press("dun", SearchKeys.BACK))
        assertEquals("", SearchKeys.press("", SearchKeys.BACK))
        assertEquals("", SearchKeys.press("dune", SearchKeys.CLEAR))
    }
}
