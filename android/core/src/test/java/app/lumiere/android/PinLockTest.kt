package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PinLockTest {
    @Test fun theRightPinMatchesAndOthersDont() {
        val sealed = PinLock.seal("4071")
        assertTrue(PinLock.matches(sealed, "4071"))
        assertFalse(PinLock.matches(sealed, "4070"))
        assertFalse(PinLock.matches(sealed, ""))
    }

    @Test fun theDigitsAreNotStored() {
        val sealed = PinLock.seal("4071")
        assertFalse(sealed.contains("4071"))
        assertFalse(PinLock.isPlain(sealed))
        assertNotEquals("each PIN gets its own salt", sealed, PinLock.seal("4071"))
    }

    @Test fun anEarlierVersionsPinIsRecognisedAsDigits() {
        assertTrue(PinLock.isPlain("1234"))
        assertFalse(PinLock.isPlain(""))
        assertFalse(PinLock.matches("1234", "1234"))
    }

    @Test fun aDamagedRecordMatchesNothing() {
        assertFalse(PinLock.matches("pbkdf2\$x\$y\$z", "1234"))
        assertFalse(PinLock.matches("nonsense", "1234"))
    }

    @Test fun fiveTriesFreeThenThirtySecondsDoubling() {
        val at = 1_000_000L
        assertEquals(0, PinLock.waitMs(4, at, at))
        assertEquals(30_000, PinLock.waitMs(5, at, at))
        assertEquals(60_000, PinLock.waitMs(6, at, at))
        assertEquals(120_000, PinLock.waitMs(7, at, at))
        assertEquals(10_000, PinLock.waitMs(5, at, at + 20_000))
        assertEquals(0, PinLock.waitMs(5, at, at + 31_000))
    }
}
