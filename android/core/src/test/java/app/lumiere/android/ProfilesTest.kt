package app.lumiere.android

import app.lumiere.android.api.Session
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Who's watching?": the profiles saved on a device, how an older single sign-in comes in, and where the app opens. */
class ProfilesTest {
    private val mac = "http://192.168.2.15:8098"
    private val anna = Profile(Session(mac, "a1", "Anna", "tok-a", "Living Room"), imageTag = "tagA")
    private val ben = Profile(Session(mac, "b2", "Ben", "tok-b", "Living Room"))
    private val cleo = Profile(Session("http://10.0.0.9:8098", "a1", "Cleo", "tok-c", "Cabin"))

    @Test fun profilesReadBackAsTheyWereSaved() {
        val saved = listOf(anna, ben, cleo)
        assertEquals(saved, Profiles.decode(Profiles.encode(saved)))
    }

    @Test fun aProfileWithNoPictureKeepsNone() {
        assertNull(Profiles.decode(Profiles.encode(listOf(ben))).single().imageTag)
    }

    @Test fun theSameUserOnAnotherServerIsSomeoneElse() {
        assertTrue(anna.key != cleo.key)
        assertEquals(2, Profiles.decode(Profiles.encode(listOf(anna, cleo))).size)
    }

    @Test fun anUnreadableSaveReadsAsNobody() {
        assertEquals(emptyList<Profile>(), Profiles.decode(null))
        assertEquals(emptyList<Profile>(), Profiles.decode(""))
        assertEquals(emptyList<Profile>(), Profiles.decode("{not json"))
        assertEquals(emptyList<Profile>(), Profiles.decode("[]"))
    }

    @Test fun aProfileMissingItsTokenOrServerIsLeftOut() {
        val json = """[{"server":"$mac","userId":"a1","userName":"Anna"},{"userId":"b2","token":"t"},
            {"server":"$mac","userId":"c3","userName":"Cleo","token":"tok","serverName":null,"imageTag":null}, 7]"""
        val read = Profiles.decode(json)
        assertEquals(listOf("c3"), read.map { it.session.userId })
        assertEquals("Lumiere", read.single().session.serverName)
        assertNull(read.single().imageTag)
    }

    @Test fun theSameProfileSavedTwiceReadsOnce() {
        assertEquals(1, Profiles.decode(Profiles.encode(listOf(ben, ben.copy(imageTag = "x")))).size)
    }

    @Test fun theOneSessionOfAnOlderVersionBecomesTheFirstProfile() {
        assertEquals(listOf(Profile(anna.session)), Profiles.migrate(emptyList(), anna.session))
        assertEquals(listOf(Profile(cleo.session), anna, ben), Profiles.migrate(listOf(anna, ben), cleo.session))
    }

    @Test fun aSessionAlreadySavedKeepsItsPlaceAndTakesItsNewerToken() {
        val newer = ben.session.copy(token = "tok-b2")
        val migrated = Profiles.migrate(listOf(anna, ben), newer)
        assertEquals(listOf(anna.key, ben.key), migrated.map { it.key })
        assertEquals("tok-b2", migrated[1].session.token)
        assertEquals("tagA", migrated[0].imageTag)
    }

    @Test fun nobodySignedInChangesNothing() = assertEquals(listOf(anna), Profiles.migrate(listOf(anna), null))

    @Test fun signingInAgainReplacesInPlace() {
        val again = Profile(anna.session.copy(token = "tok-a2"))
        val kept = Profiles.upsert(listOf(anna, ben), again)
        assertEquals(listOf(anna.key, ben.key), kept.map { it.key })
        assertEquals("tok-a2", kept[0].session.token)
        assertEquals(listOf(anna, ben, cleo), Profiles.upsert(listOf(anna, ben), cleo))
    }

    @Test fun removingSomeoneElseCarriesOn() {
        val (rest, then) = Profiles.remove(listOf(anna, ben, cleo), ben.key, anna.key)
        assertEquals(listOf(anna, cleo), rest)
        assertEquals(Profiles.Start.Home, then)
    }

    @Test fun removingTheOneWatchingAsksWhoIsWatching() {
        val (rest, then) = Profiles.remove(listOf(anna, ben), anna.key, anna.key)
        assertEquals(listOf(ben), rest)
        assertEquals(Profiles.Start.Choose, then)
    }

    @Test fun removingTheLastOneSignsInAfresh() {
        val (rest, then) = Profiles.remove(listOf(anna), anna.key, anna.key)
        assertEquals(emptyList<Profile>(), rest)
        assertEquals(Profiles.Start.SignIn, then)
    }

    @Test fun theStartScreen() {
        assertEquals(Profiles.Start.SignIn, Profiles.start(profiles = 0, signedIn = false, askAtStart = true))
        assertEquals(Profiles.Start.Home, Profiles.start(profiles = 1, signedIn = true, askAtStart = true))
        assertEquals(Profiles.Start.Choose, Profiles.start(profiles = 2, signedIn = true, askAtStart = true))
        assertEquals(Profiles.Start.Home, Profiles.start(profiles = 2, signedIn = true, askAtStart = false))
        assertEquals(Profiles.Start.Choose, Profiles.start(profiles = 3, signedIn = true, askAtStart = true))
        // Signed out with someone still saved: choose, whatever the setting.
        assertEquals(Profiles.Start.Choose, Profiles.start(profiles = 1, signedIn = false, askAtStart = false))
    }

    @Test fun switchingPutsTheLastPersonsThingsAwayAndBringsTheNextOnesBack() {
        val store = mutableMapOf("recentSearches" to "dune", "watchlist" to "1,2", "recentSearches@B" to "alien")
        Profiles.swap(listOf("recentSearches", "watchlist"), { store[it] }, from = "A", to = "B").forEach { (k, v) ->
            if (v == null) store.remove(k) else store[k] = v
        }
        assertEquals(mapOf("recentSearches" to "alien", "recentSearches@A" to "dune", "watchlist@A" to "1,2"), store)
        // And back again: as it was.
        Profiles.swap(listOf("recentSearches", "watchlist"), { store[it] }, from = "B", to = "A").forEach { (k, v) ->
            if (v == null) store.remove(k) else store[k] = v
        }
        assertEquals(mapOf("recentSearches" to "dune", "watchlist" to "1,2", "recentSearches@B" to "alien"), store)
    }

    @Test fun someoneSignedOutLeavesNothingBehind() {
        val store = mutableMapOf("recentSearches" to "dune")
        Profiles.swap(listOf("recentSearches"), { store[it] }, from = null, to = "B").forEach { (k, v) ->
            if (v == null) store.remove(k) else store[k] = v
        }
        assertEquals(emptyMap<String, String>(), store)
    }

    @Test fun choosingTheSamePersonMovesNothing() =
        assertEquals(emptyMap<String, String?>(), Profiles.swap(listOf("watchlist"), { "x" }, from = "A", to = "A"))

    @Test fun anInitialIsOneLetterOrOneWholeEmoji() {
        assertEquals("A", Profiles.initial("  anna"))
        assertEquals("É", Profiles.initial("élodie"))
        assertEquals("🍿", Profiles.initial("🍿 popcorn"))
        assertEquals("?", Profiles.initial(" "))
    }

    @Test fun aPersonAlwaysWearsTheSameColour() {
        assertEquals(Profiles.tint(anna.key, 6), Profiles.tint(anna.key, 6))
        listOf(anna, ben, cleo).forEach { assertTrue(Profiles.tint(it.key, 6) in 0 until 6) }
        assertTrue((0..200).map { Profiles.tint("$mac|user$it", 6) }.toSet().size == 6)
    }
}
