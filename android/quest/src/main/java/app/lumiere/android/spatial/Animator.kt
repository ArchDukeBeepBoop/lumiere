package app.lumiere.android.spatial

import com.meta.spatial.core.SystemBase

/**
 * Each frame, what moves in a place is moved (Director.animate): a flame
 * can't flicker at the Director's four looks a second. Guarded: this runs
 * on the SDK's frame loop, where a failure would stop the app.
 */
class Animator(private val director: () -> Director?) : SystemBase() {
    private val started = System.nanoTime()

    override fun execute() {
        runCatching { director()?.animate((System.nanoTime() - started) / 1e9f) }
    }
}
