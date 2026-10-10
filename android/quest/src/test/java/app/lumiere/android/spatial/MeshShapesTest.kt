package app.lumiere.android.spatial

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The SDK's built-in meshes read their size from a component on the same
 * entity, and throw from the SDK's own mesh system when it is missing — on
 * the next frame, where nothing of ours can catch it, so the app stops.
 * The theatre's floor and stage were `mesh://box` without a Box, and every
 * start crashed. Every built-in shape made here must carry its component.
 */
class MeshShapesTest {
    private val sources = (File("src/main/java").takeIf { it.exists() } ?: File("quest/src/main/java"))

    /** Each built-in mesh and the component its creator reads (ToolkitFeature, SDK 0.14). */
    private val needs = mapOf(
        "box" to "Box(", "sphere" to "Sphere(", "plane" to "Plane(", "quad" to "Quad(",
        "roundedbox" to "RoundedBox(", "dome" to "Dome(",
        // The sky reads its picture from a Material (without one, a plain grey ball).
        "skybox" to "Material(",
    )

    @Test fun everyBuiltInMeshCarriesItsShape() {
        val files = sources.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("no sources at $sources", files.isNotEmpty())
        files.forEach { f ->
            val text = f.readText()
            Regex(""""mesh://(\w+)""").findAll(text).forEach { m ->
                val needed = needs[m.groupValues[1].lowercase()] ?: return@forEach
                // The components given with it: the enclosing listOf( … ).
                val start = text.lastIndexOf("listOf(", m.range.first)
                if (start < 0) fail("${f.name}: mesh://${m.groupValues[1]} isn't made with a listOf(...) this test can read")
                val list = enclosed(text, start + "listOf".length)
                if (!list.contains(needed)) fail("${f.name}: mesh://${m.groupValues[1]} has no $needed component; the SDK would stop the app")
            }
        }
    }

    /** The text between the bracket at [open] and its partner. */
    private fun enclosed(text: String, open: Int): String {
        var depth = 0
        for (i in open until text.length) {
            when (text[i]) { '(' -> depth++; ')' -> if (--depth == 0) return text.substring(open, i + 1) }
        }
        return text.substring(open)
    }
}
