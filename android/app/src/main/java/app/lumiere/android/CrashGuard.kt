package app.lumiere.android

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * A bad build must never strand a device that can only update itself.
 *
 * Every crash is written down — the last one is sent to the Mac on the next
 * start that reaches a server — and a start that crashes before its first frame
 * is counted. Two in a row and the app opens in a plain safe mode, drawn with
 * Android's own views and none of the app's screens, offering only Install
 * Update and Send Diagnostics.
 */
object CrashGuard {
    private fun prefs(context: Context) = context.getSharedPreferences("lumiere.crash", Context.MODE_PRIVATE)

    /** Called first in onCreate: records crashes, counts starts that never drew. */
    fun starting(context: Context) {
        val p = prefs(context)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                p.edit().putString("lastCrash", "app ${BuildConfig.VERSION_NAME}: " + error.stackTraceToString().take(6000)).commit()
            }
            previous?.uncaughtException(thread, error)
        }
        val unfinished = p.getBoolean("starting", false)
        p.edit().putBoolean("starting", true)
            .putInt("failedStarts", if (unfinished) p.getInt("failedStarts", 0) + 1 else 0).commit()
    }

    /** The first frame is on screen: this start counts as good. */
    fun started(context: Context) = prefs(context).edit().putBoolean("starting", false).putInt("failedStarts", 0).apply()

    fun needsSafeMode(context: Context) = prefs(context).getInt("failedStarts", 0) >= 2

    /** The last crash, taken once, for diagnostics. */
    fun takeCrash(context: Context): String? = prefs(context).getString("lastCrash", null)?.also {
        prefs(context).edit().remove("lastCrash").apply()
    }

    /** Safe mode: plain views on a plain ground, nothing from the app's own screens. */
    fun showSafeMode(activity: Activity) {
        activity.window.setBackgroundDrawable(ColorDrawable(Color.rgb(28, 28, 30)))
        val saved = activity.getSharedPreferences("lumiere", Context.MODE_PRIVATE)
        val url = saved.getString("server", null)
        val token = saved.getString("token", null)
        val deviceId = saved.getString("deviceId", "safe-mode") ?: "safe-mode"
        val server = if (url != null && token != null) app.lumiere.android.api.Server(url, deviceId, token) else null
        val status = TextView(activity).apply { setTextColor(Color.LTGRAY); textSize = 16f; gravity = Gravity.CENTER }
        fun button(label: String, action: () -> Unit) = Button(activity).apply {
            text = label; textSize = 18f; setOnClickListener { action() }
        }
        val install = button("Install Update") {
            if (server == null) { status.text = "Not signed in on this device."; return@button }
            status.text = "Fetching the update…"
            CoroutineScope(Dispatchers.Main).launch {
                status.text = Updater.install(activity, server) ?: "Confirm the install on screen."
            }
        }
        val send = button("Send Diagnostics") {
            if (server == null) { status.text = "Not signed in on this device."; return@button }
            CoroutineScope(Dispatchers.Main).launch {
                takeCrash(activity)?.let { Diagnostics.note(it) }
                status.text = if (Diagnostics.send(server)) "Sent to the Mac." else "Couldn't reach the Mac."
            }
        }
        val again = button("Try Normal Start") {
            prefs(activity).edit().putInt("failedStarts", 0).putBoolean("starting", false).commit()
            activity.recreate()
        }
        val layout = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(80, 80, 80, 80)
            addView(TextView(activity).apply {
                text = "Lumiere didn't start properly"; setTextColor(Color.WHITE); textSize = 26f; gravity = Gravity.CENTER
            })
            addView(TextView(activity).apply {
                text = "Install the latest version from the Mac, or send what went wrong."
                setTextColor(Color.LTGRAY); textSize = 16f; gravity = Gravity.CENTER; setPadding(0, 16, 0, 32)
            })
            addView(install); addView(send); addView(again); addView(status)
        }
        activity.setContentView(layout)
        install.requestFocus()
    }
}
