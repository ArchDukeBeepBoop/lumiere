package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RecentSearchesTest {
    @Test fun theNewestComesFirst() {
        assertEquals(listOf("dune", "alien"), RecentSearches.add(listOf("alien"), "dune"))
    }

    @Test fun theSameWordsInAnotherCaseAreOneSearchMovedToTheFront() {
        assertEquals(listOf("Alien", "dune"), RecentSearches.add(listOf("dune", "alien"), "Alien"))
        assertEquals(listOf("the bear", "dune"), RecentSearches.add(listOf("dune", " The Bear "), "  the bear"))
    }

    @Test fun onlyTheLastEightAreKept() {
        val ten = (1..10).fold(emptyList<String>()) { list, i -> RecentSearches.add(list, "search $i") }
        assertEquals(8, ten.size)
        assertEquals("search 10", ten.first())
        assertEquals("search 3", ten.last())
    }

    @Test fun aBlankTermChangesNothing() {
        assertEquals(listOf("dune"), RecentSearches.add(listOf("dune"), "   "))
    }

    @Test fun whatWasSavedComesBackTheSame() {
        val list = listOf("dune", "the bear", "Alien")
        assertEquals(list, RecentSearches.decode(RecentSearches.encode(list)))
        assertEquals(emptyList<String>(), RecentSearches.decode(null))
        assertEquals(emptyList<String>(), RecentSearches.decode(""))
    }

    @Test fun anEarlierVersionsListLoadsTidied() {
        assertEquals(listOf("Dune", "alien"), RecentSearches.decode("Dune\n\n dune\n alien \nALIEN"))
        val long = (1..12).joinToString("\n") { "s$it" }
        assertEquals(8, RecentSearches.decode(long).size)
    }

    @Test fun theRecognisersBestGuessIsTaken() {
        assertEquals("the bear", RecentSearches.heard(listOf(" the bear ", "the bare")))
        assertEquals("dune", RecentSearches.heard(listOf("", null, "dune")))
        assertNull(RecentSearches.heard(emptyList()))
        assertNull(RecentSearches.heard(null))
    }
}
