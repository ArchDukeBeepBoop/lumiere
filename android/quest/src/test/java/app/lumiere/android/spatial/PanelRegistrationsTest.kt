package app.lumiere.android.spatial

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Every panel the app makes must be registered first: the SDK's panel
 * system throws "No panel creator found" on the next frame otherwise,
 * outside anything that could catch it, and the app stops at every start.
 * The poster wall lost its registration in one change and did exactly that.
 */
class PanelRegistrationsTest {
    private val sources = (File("src/main/java").takeIf { it.exists() } ?: File("quest/src/main/java"))

    @Test fun everyPanelMadeIsRegistered() {
        val files = sources.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("no sources at $sources", files.isNotEmpty())
        val text = files.joinToString("\n") { it.readText() }
        // Registered: the id given first to a …PanelRegistration(.
        val registered = Regex("""PanelRegistration\(\s*R\.id\.(\w+)""").findAll(text).map { it.groupValues[1] }.toSet()
        // Made: the id given first to createPanelEntity(.
        val made = Regex("""createPanelEntity\(\s*R\.id\.(\w+)""").findAll(text).map { it.groupValues[1] }.toSet()
        assertTrue("found the panels made: $made", made.size >= 5)
        (made - registered).forEach { fail("R.id.$it is made with createPanelEntity but never registered in registerPanels()") }
    }
}
