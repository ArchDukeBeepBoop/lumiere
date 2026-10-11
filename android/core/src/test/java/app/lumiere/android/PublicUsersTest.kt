package app.lumiere.android

import app.lumiere.android.api.parsePublicUsers
import app.lumiere.android.api.userImageUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Add Profile's faces: the people a server lists before sign-in, and where their pictures are. */
class PublicUsersTest {
    // As a Jellyfin server answers Users/Public, trimmed.
    private val jellyfin = """[
        {"Name":"Anna","ServerId":"s","Id":"a1","PrimaryImageTag":"9f2c","HasPassword":true,"HasConfiguredPassword":true},
        {"Name":"Kids","ServerId":"s","Id":"k2","HasPassword":false,"HasConfiguredPassword":false},
        {"Name":"Guest","Id":"g3","PrimaryImageTag":null}
    ]"""

    @Test fun eachPersonListedIsOffered() {
        val users = parsePublicUsers(jellyfin)
        assertEquals(listOf("Anna", "Kids", "Guest"), users.map { it.name })
        assertEquals("9f2c", users[0].imageTag)
        assertNull(users[1].imageTag)
        assertNull(users[2].imageTag)
    }

    @Test fun aPasswordIsAskedUnlessTheServerSaysThereIsNone() {
        val users = parsePublicUsers(jellyfin)
        assertTrue(users[0].hasPassword)
        assertFalse(users[1].hasPassword)
        // Saying nothing: asked, as an empty field is quicker to pass than a refusal is to understand.
        assertTrue(users[2].hasPassword)
    }

    @Test fun lumieresOwnServerListsNobody() = assertEquals(0, parsePublicUsers("[]").size)

    @Test fun anAnswerThatIsNotAListOffersNobody() {
        assertEquals(0, parsePublicUsers("""{"Items":[]}""").size)
        assertEquals(0, parsePublicUsers("<html>").size)
        assertEquals(0, parsePublicUsers("""[{"Name":"No id"}]""").size)
    }

    @Test fun aPictureIsAskedForAtItsSizeAndTag() {
        assertEquals("http://192.168.2.15:8098/Users/a1/Images/Primary?tag=9f2c&maxWidth=240&quality=90",
            userImageUrl("http://192.168.2.15:8098/", "a1", "9f2c", 240))
    }

    @Test fun anAddressThatIsNotOneHasNoPicture() = assertNull(userImageUrl("not a server", "a1", "t", 120))
}
