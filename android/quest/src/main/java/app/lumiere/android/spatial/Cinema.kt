package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.player.PictureInPicture
import app.lumiere.android.ui.Ambient
import com.meta.spatial.core.Entity
import com.meta.spatial.core.Lut
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Scale
import com.meta.spatial.toolkit.Visible
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Cinema mode: when a film plays the room's lights go down, a little of the
 * film's colour spills onto the walls, the window grows into a screen and
 * the sidebar steps away; pausing brings the lights half up. Four looks a
 * second at the app's state; the passthrough table and the window's size
 * change only while they're moving, so a film costs the headset nothing.
 */
class Cinema(private val scene: Scene, private val window: Entity, private val sidebar: Entity) {
    private var brightness = CinemaLight.LIT
    private var shownBrightness = -1f
    private var shownTint: Triple<Float, Float, Float>? = null
    private var size = 1f
    private var sidebarShown = true

    fun start(scope: CoroutineScope): Job = scope.launch {
        while (isActive) {
            val inPlayer = OpenApp.state?.top is Screen.Player
            val playing = PictureInPicture.playing
            val reduced = app.lumiere.android.Motion.reduced
            val target = CinemaLight.target(inPlayer, playing)
            brightness = if (reduced) target else CinemaLight.ease(brightness, target)
            light(brightness, Ambient.colour?.let { Triple(it.red, it.green, it.blue) })
            val wanted = if (inPlayer) SCREEN_SCALE else 1f
            size = if (reduced) wanted else CinemaLight.ease(size, wanted)
            window.setComponent(Scale(Vector3(size)))
            if (sidebarShown == inPlayer) {
                sidebarShown = !inPlayer
                sidebar.setComponent(Visible(sidebarShown))
            }
            delay(if (brightness == target && size == wanted) 250 else 60)
        }
    }

    private fun light(level: Float, tint: Triple<Float, Float, Float>?) {
        if (level == shownBrightness && tint == shownTint) return
        shownBrightness = level; shownTint = tint
        val (r, g, b) = tint ?: Triple(0f, 0f, 0f)
        val table = Lut()
        for (x in 0..15) for (y in 0..15) for (z in 0..15) {
            table.setMapping(x, y, z, CinemaLight.channel(x, level, r), CinemaLight.channel(y, level, g), CinemaLight.channel(z, level, b))
        }
        runCatching { scene.setPassthroughLUT(table) }
    }

    companion object {
        /** The window during a film: a third larger again, from where you sit. */
        const val SCREEN_SCALE = 1.35f
    }
}
