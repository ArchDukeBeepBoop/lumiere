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

    @Test fun launchWindowUsesARealPicture() {
        val boot = File(main, "res/drawable/boot.xml").readText()
        Regex("""android:src="@(\w+)/(\w+)"""").findAll(boot).forEach { m ->
            val (folder, name) = m.destructured
            assertTrue("boot.xml draws @$folder/$name, which must be a picture, not a mipmap", folder == "drawable")
            val png = main.resolve("res").listFiles().orEmpty().filter { it.name.startsWith("drawable") }
                .any { File(it, "$name.png").exists() || File(it, "$name.webp").exists() }
            assertTrue("boot.xml draws @drawable/$name, which has no PNG", png)
        }
    }

    @Test fun noScreenPaintsTheLauncherIcon() {
        main.resolve("java").walkTopDown().filter { it.extension == "kt" }.forEach { f ->
            if (Regex("""painterResource\([^)]*R\.mipmap\.""").containsMatchIn(f.readText()))
                fail("${f.name} paints a mipmap; the launcher icon is XML on Android 8+ and crashes painterResource")
        }
    }
}
