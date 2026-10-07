package app.lumiere.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * What the app draws before its first frame must be a real picture. The
 * launcher icon is an adaptive-icon XML on Android 8+, which neither a
 * <bitmap> nor painterResource can draw — 1.277.1081 crashed at every start
 * because of it, and a crashed app cannot update itself.
 */
class StartupResourcesTest {
    private val main = File("src/main").takeIf { it.exists() } ?: File("app/src/main")
    /** The screens and their pictures live in the shared module beside this one. */
    private val shared = main.resolve("../../../screens/src/main").normalize()

    @Test fun launchWindowUsesARealPicture() {
        val boot = File(main, "res/drawable/boot.xml").readText()
        Regex("""android:src="@(\w+)/(\w+)"""").findAll(boot).forEach { m ->
            val (folder, name) = m.destructured
            assertTrue("boot.xml draws @$folder/$name, which must be a picture, not a mipmap", folder == "drawable")
            val png = listOf(main, shared).flatMap { it.resolve("res").listFiles().orEmpty().toList() }.filter { it.name.startsWith("drawable") }
                .any { File(it, "$name.png").exists() || File(it, "$name.webp").exists() }
            assertTrue("boot.xml draws @drawable/$name, which has no PNG", png)
        }
    }

    @Test fun noScreenPaintsTheLauncherIcon() {
        assertTrue("the shared screens weren't found at $shared", shared.resolve("java").isDirectory)
        listOf(main, shared).flatMap { it.resolve("java").walkTopDown().toList() }.filter { it.extension == "kt" }.forEach { f ->
            if (Regex("""painterResource\([^)]*R\.mipmap\.""").containsMatchIn(f.readText()))
                fail("${f.name} paints a mipmap; the launcher icon is XML on Android 8+ and crashes painterResource")
        }
    }
}
