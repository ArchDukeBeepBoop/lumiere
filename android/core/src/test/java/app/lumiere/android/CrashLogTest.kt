package app.lumiere.android

import java.util.Date
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CrashLogTest {
    @Test fun aReportNamesTheBuildAndEveryCause() {
        AppBuild.set("1.2.3-spatial", 42, quest = true)
        val error = RuntimeException("Box mesh creation failed", IllegalStateException("no Box on entity 7"))
        val text = CrashLog.report("main", error, Date(0))
        assertTrue(text, text.contains("Build 1.2.3-spatial (42), Quest"))
        assertTrue(text, text.contains("Thread main"))
        assertTrue(text, text.contains("Box mesh creation failed"))
        assertTrue("the cause is kept", text.contains("Caused by: java.lang.IllegalStateException: no Box on entity 7"))
    }

    @Test fun twoFailedStartsInARowMakeTheNextPlain() {
        assertFalse(StartGuard.plain(0))
        assertFalse(StartGuard.plain(1))
        assertTrue(StartGuard.plain(StartGuard.TRIPS))
    }
}
