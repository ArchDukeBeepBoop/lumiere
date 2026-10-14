package app.lumiere.android.widget

import app.lumiere.android.Launch
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import app.lumiere.android.screens.R
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.privateLibraries
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Continue Watching on the home screen: three titles, each a tap from
 * carrying on. Nothing from a private library ever shows here — the home
 * screen is the most public screen the phone has.
 */
class ResumeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try { refresh(context, manager, ids) } finally { pending.finish() }
        }
    }

    companion object {
        const val OPEN = "app.lumiere.android.OPEN_ITEM"

        /** Asked for by the app whenever Home reloads, so the widget keeps up. */
        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ResumeWidget::class.java))
            if (ids.isEmpty()) return
            CoroutineScope(Dispatchers.IO).launch { runCatching { refresh(context, manager, ids) } }
        }

        private suspend fun refresh(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences("lumiere", Context.MODE_PRIVATE)
            val local = context.getSharedPreferences("lumiere.prefs", Context.MODE_PRIVATE)
            val url = prefs.getString("server", null)
            val token = prefs.getString("token", null)
            val userId = prefs.getString("userId", null)
            val device = prefs.getString("deviceId", "") ?: ""
            var items: List<Item> = emptyList()
            if (url != null && token != null && userId != null) {
                runCatching {
                    val server = Server(url, device, token)
                    val hidden = if (local.getBoolean("privateFollowsMac", true)) server.privateLibraries()
                        else local.getStringSet("privateLibraries", emptySet())!!
                    // Unknown library is left out too: when in doubt, not on the home screen.
                    items = server.resume(userId).filter { it.libraryId != null && it.libraryId !in hidden }.take(3)
                }
            }
            val rows = listOf(R.id.widget_row1, R.id.widget_row2, R.id.widget_row3)
            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.widget_resume)
                rows.forEachIndexed { i, row ->
                    val item = items.getOrNull(i)
                    if (item == null) {
                        views.setViewVisibility(row, if (i == 0) View.VISIBLE else View.GONE)
                        if (i == 0) views.setTextViewText(row, if (token == null) "Sign in to Lumiere" else "Nothing in progress")
                        views.setOnClickPendingIntent(row, open(context, null, i))
                    } else {
                        views.setViewVisibility(row, View.VISIBLE)
                        views.setTextViewText(row, label(item))
                        views.setOnClickPendingIntent(row, open(context, item.id, i))
                    }
                }
                manager.updateAppWidget(id, views)
            }
        }

        private fun label(item: Item): String {
            val left = item.runtimeTicks?.let { ((it - item.positionTicks) / 600_000_000L).coerceAtLeast(1) }
            val name = if (item.isEpisode) "${item.seriesName} · ${item.episodeLabel ?: item.name}" else item.name
            return name + (left?.let { " — $it min left" } ?: "")
        }

        private fun open(context: Context, itemId: String?, slot: Int): PendingIntent {
            val intent = Launch.intent(context).apply {
                action = OPEN
                itemId?.let { putExtra("item", it) }
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(context, slot, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
