package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Private Room stood empty when the Mac spelt a library's id another way. */
class RoomLibrariesTest {
    private val views = listOf("f137a2dd21bbc1b99aa5c0f6bf02a805", "0c41907140d802bb58430fed7e2cd79e")

    @Test fun theMacsSpellingIsMatchedToThisAccounts() {
        val fromMac = setOf("F137A2DD-21BB-C1B9-9AA5-C0F6BF02A805")
        assertEquals(setOf(views[0]), RoomLibraries.match(fromMac, views))
    }

    @Test fun anIdWithNoLibraryHereIsKept() {
        assertEquals(setOf("elsewhere"), RoomLibraries.match(setOf("elsewhere"), views))
    }

    @Test fun beforeTheLibrariesAreKnownNothingChanges() {
        val fromMac = setOf("ABC-DEF")
        assertEquals(fromMac, RoomLibraries.match(fromMac, emptyList()))
        assertTrue(RoomLibraries.match(emptySet(), views).isEmpty())
    }

    @Test fun sameIgnoresDashesAndCapitals() {
        assertTrue(RoomLibraries.same("ab-cd", "ABCD"))
        assertTrue(!RoomLibraries.same("abcd", "abce"))
    }
}
