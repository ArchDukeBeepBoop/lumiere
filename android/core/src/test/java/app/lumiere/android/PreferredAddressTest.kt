package app.lumiere.android

import app.lumiere.android.api.FoundServer
import app.lumiere.android.api.preferredAddress
import org.junit.Assert.assertEquals
import org.junit.Test

class PreferredAddressTest {
    private val mac = FoundServer("Lumiere", "http://192.168.2.15:8098", "id")

    @Test fun aStaleSavedAddressGivesWayToTheServerFound() =
        assertEquals(mac.address, preferredAddress("http://192.168.2.40:8098", listOf(mac), savedAnswers = false))

    @Test fun aSavedAddressThatAnswersIsKept() =
        assertEquals("http://10.0.0.9:8098", preferredAddress("http://10.0.0.9:8098", listOf(mac), savedAnswers = true))

    @Test fun theSavedAddressMatchingTheOneFoundIsKept() =
        assertEquals("http://192.168.2.15:8098/", preferredAddress("http://192.168.2.15:8098/", listOf(mac), savedAnswers = false))

    @Test fun nothingSavedTakesTheOneFound() = assertEquals(mac.address, preferredAddress(null, listOf(mac), false))

    @Test fun twoFoundAndAStaleSaveLeavesTheChoiceToYou() {
        val other = FoundServer("Other", "http://192.168.2.20:8098", "x")
        assertEquals("http://192.168.2.40:8098", preferredAddress("http://192.168.2.40:8098", listOf(mac, other), false))
    }

    @Test fun nothingAtAllStaysEmpty() = assertEquals(null, preferredAddress(null, emptyList(), false))
}
