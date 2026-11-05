package app.lumiere.android.spatial

import app.lumiere.android.MainActivity
import app.lumiere.android.OpenApp

/**
 * The film's host inside the theater: Lumiere's own window, embedded in the
 * theater's panel and kept out of sight, playing the film it was opened for
 * (OpenApp.pendingPlay) onto the theater's screen. It shows only for a
 * question the player asks (resume, still watching, an error). Browsing
 * happens in the lobby's window, never here.
 */
class TheaterWindow : MainActivity() {
    override val inRoom: Boolean get() = true

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        OpenApp.pendingPlay?.let { play(it); OpenApp.pendingPlay = null }
    }
}
