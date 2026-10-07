package app.lumiere.android.music

import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Keeps music going with the screen off. Media3 draws the notification and
 * the lock-screen controls from this session, and stops being a foreground
 * service by itself once playback stops.
 */
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        val player = current() ?: return null
        if (session?.player !== player) {
            session?.release()
            session = build(player)
        }
        return session
    }

    override fun onCreate() {
        super.onCreate()
        current()?.let { session = build(it).also(::addSession) }
        running = this
    }

    /** A video playing in the background takes the session from music while it lasts. */
    private fun current(): androidx.media3.common.Player? = video ?: Music.player

    private fun swap() {
        val p = current() ?: return
        val s = session
        if (s == null) session = build(p).also(::addSession) else if (s.player !== p) s.player = p
    }

    companion object {
        private var running: PlaybackService? = null
        /** The video on the lock screen, or null to hand it back to music. */
        var video: androidx.media3.common.Player? = null
            set(v) { field = v; running?.swap() }
    }

    /**
     * Album art on the lock screen and notification is fetched with the
     * signed-in client: the server wants the token for pictures too, and the
     * default loader has none, so the art never arrived.
     */
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun build(player: androidx.media3.common.Player): MediaSession {
        val builder = MediaSession.Builder(this, player)
        Music.server?.let { server ->
            builder.setBitmapLoader(androidx.media3.datasource.DataSourceBitmapLoader(
                com.google.common.util.concurrent.MoreExecutors.listeningDecorator(
                    java.util.concurrent.Executors.newSingleThreadExecutor()),
                androidx.media3.datasource.okhttp.OkHttpDataSource.Factory(server.http),
            ))
        }
        return builder.build()
    }

    override fun onDestroy() {
        running = null
        session?.release()
        session = null
        super.onDestroy()
    }
}
