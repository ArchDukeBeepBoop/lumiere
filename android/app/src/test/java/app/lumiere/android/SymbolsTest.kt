package app.lumiere.android

import app.lumiere.android.ui.Symbols
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SymbolsTest {
    @Test fun everySymbolBuildsOnTheGrid() {
        val all = Symbols.all
        assertEquals(all.size, all.map { it.name }.toSet().size)
        all.forEach {
            assertEquals(24f, it.viewportWidth); assertEquals(24f, it.viewportHeight)
            assertTrue(it.name, it.root.size > 0)
        }
    }
}
