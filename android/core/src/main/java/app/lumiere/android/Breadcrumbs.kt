package app.lumiere.android

import android.content.Context

/**
 * How far each start got, written as it goes (committed at once, so a crash a
 * moment later can't lose it): a crash in native code leaves no report of its
 * own, but the next start can say which step the last one reached. Diagnostics
 * shows the last start's trail and this one's.
 */
object Breadcrumbs {
    private var app: Context? = null
    private var started = 0L

    fun begin(context: Context) {
        val c = context.applicationContext
        app = c
        started = System.currentTimeMillis()
        val p = prefs(c)
        p.edit().putString("previous", p.getString("trail", "")).putString("trail", "").commit()
        mark("start")
    }

    @Synchronized
    fun mark(step: String) {
        val c = app ?: return
        val p = prefs(c)
        val line = "+${System.currentTimeMillis() - started}ms $step"
        val trail = (p.getString("trail", "") ?: "").lines().filter { it.isNotBlank() }.takeLast(60) + line
        p.edit().putString("trail", trail.joinToString("\n")).commit()
    }

    fun previous(context: Context): String = prefs(context).getString("previous", "") ?: ""
    fun current(context: Context): String = prefs(context).getString("trail", "") ?: ""

    private fun prefs(c: Context) = c.getSharedPreferences("breadcrumbs", Context.MODE_PRIVATE)
}
