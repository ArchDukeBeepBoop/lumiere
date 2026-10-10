package app.lumiere.android.widget

import app.lumiere.android.Launch
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import app.lumiere.android.screens.R
import app.lumiere.android.music.Music

/**
 * The song playing, on the home screen, with play or pause and next. Music
 * from a private library shows only "Lumiere" — the home screen is the most
 * public screen the phone has.
 */
class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = update(context)

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            TOGGLE -> Music.toggle()
            NEXT -> Music.next()
        }
        super.onReceive(context, intent)
        if (intent.action == TOGGLE || intent.action == NEXT) update(context)
    }

    companion object {
        private const val TOGGLE = "app.lumiere.android.widget.TOGGLE"
        private const val NEXT = "app.lumiere.android.widget.NEXT"

        /** Called by Music whenever the song or play state changes. */
        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java))
            if (ids.isEmpty()) return
            val track = Music.current?.takeIf { !Music.isPlayingFromRoom }
            val views = RemoteViews(context.packageName, R.layout.widget_now_playing)
            views.setTextViewText(R.id.np_title, track?.name ?: if (Music.current != null) "Lumiere" else "Nothing playing")
            views.setTextViewText(R.id.np_artist, track?.let { it.artists.joinToString(", ").ifEmpty { it.albumArtist ?: "" } } ?: "")
            views.setImageViewResource(R.id.np_toggle,
                if (Music.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
            views.setOnClickPendingIntent(R.id.np_toggle, action(context, TOGGLE, 1))
            views.setOnClickPendingIntent(R.id.np_next, action(context, NEXT, 2))
            views.setOnClickPendingIntent(R.id.np_root, PendingIntent.getActivity(context, 3,
                Launch.intent(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            manager.updateAppWidget(ids, views)
        }

        private fun action(context: Context, name: String, code: Int): PendingIntent =
            PendingIntent.getBroadcast(context, code, Intent(context, NowPlayingWidget::class.java).setAction(name),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
