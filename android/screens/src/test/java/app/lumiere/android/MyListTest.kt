package app.lumiere.android

import app.lumiere.android.api.Item
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** + My List changes on screen at once, and goes back when the Mac refuses it. */
class MyListTest {
    private val arrival = Item("a", "Arrival", "Movie")
    private val dune = Item("d", "Dune", "Movie", favorite = true)

    @Test fun pressingShowsTheChangeBeforeTheServerAnswers() {
        val list = MyList("me")
        assertEquals(true, list.toggle(arrival))
        assertTrue(list.has(arrival))
        assertNull("nothing more to send", list.sent("a", true))
        assertTrue(list.has(arrival))
    }

    @Test fun aRefusalPutsItBack() {
        val list = MyList("me")
        list.toggle(arrival)
        list.failed("a")
        assertFalse(list.has(arrival))
        list.toggle(dune)
        list.failed("d")
        assertTrue("taken out, refused: still in", list.has(dune))
    }

    @Test fun aRefusalGoesBackToWhatTheServerLastHadNotToTheStart() {
        val list = MyList("me")
        list.toggle(arrival); list.sent("a", true)
        list.toggle(arrival)
        list.failed("a")
        assertTrue(list.has(arrival))
    }

    @Test fun pressedAgainWhileSendingTheNewestChoiceFollows() {
        val list = MyList("me")
        assertEquals(true, list.toggle(arrival))
        assertNull("already on its way: this one goes after it", list.toggle(arrival))
        assertFalse(list.has(arrival))
        assertEquals(false, list.sent("a", true))
        assertNull(list.sent("a", false))
        assertFalse(list.has(arrival))
        // Done sending: the next press sends straight away again.
        assertEquals(true, list.toggle(arrival))
    }

    @Test fun homesRowShowsYourChangesAtOnce() {
        val list = MyList("me")
        val heat = Item("h", "Heat", "Movie", favorite = true)
        val album = Item("m", "Blue", "MusicAlbum")
        list.toggle(arrival)
        list.toggle(album)
        list.toggle(dune)
        assertEquals(listOf(arrival, heat), list.over(listOf(dune, heat)))
        // Once the server has it, it's there once, in the server's place.
        assertEquals(listOf(heat, arrival), list.over(listOf(heat, arrival)))
    }

    @Test fun theNewestAddedComesFirst() {
        val list = MyList("me")
        val heat = Item("h", "Heat", "Movie")
        list.toggle(arrival); list.toggle(heat)
        assertEquals(listOf(heat, arrival), list.over(emptyList()))
    }

    @Test fun untouchedTitlesFollowTheServer() {
        val list = MyList("me")
        assertTrue(list.has(dune))
        assertFalse(list.has(arrival))
        assertEquals(listOf(dune), list.over(listOf(dune)))
    }
}
