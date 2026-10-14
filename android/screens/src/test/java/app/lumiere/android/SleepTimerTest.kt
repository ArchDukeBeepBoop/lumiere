package app.lumiere.android

import org.junit.Assert.assertEquals
import org.junit.Test

class SleepTimerTest {
    @Test fun eachPressIsTheNextStepThenOff() {
        Stage.sleepDone()
        val now = 1_000_000L
        val seen = (1..5).map { Stage.cycleSleep(now); Stage.sleepMinutes to Stage.sleepAt }
        assertEquals(listOf(15, 30, 60, 90, 0), seen.map { it.first })
        assertEquals(now + 15 * 60_000L, seen[0].second)
        assertEquals(0L, seen[4].second)
    }
}
