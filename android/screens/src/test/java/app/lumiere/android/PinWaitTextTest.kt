package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Test

class PinWaitTextTest {
    @Test fun waitsReadAsPeopleSayThem() {
        assertEquals("30 seconds", waitText(30_000))
        assertEquals("1 second", waitText(400))
        assertEquals("1 minute", waitText(60_000))
        assertEquals("2 minutes", waitText(61_000))
        assertEquals("4 minutes", waitText(240_000))
    }
}
