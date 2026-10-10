package app.lumiere.android

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What stopped Lumiere, written down where you can reach it without a
 * computer's Terminal: Downloads › Lumiere on the device (the headset's
 * Files app, or SideQuest's file browser), one text file a crash. A copy
 * stays in the app's own storage for [last].
 *
 * Only a crash in Kotlin or Java is caught this way; one in native code
 * stops the process before any handler runs, which [StartGuard] covers.
 */
object CrashLog {
    private const val FILE = "last-crash.txt"

    fun install(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { record(app, report(thread.name, error, Date())) }
            previous?.uncaughtException(thread, error)
        }
    }

    /** The newest report, if the app has stopped since it was installed. */
    fun last(context: Context): String? = File(context.filesDir, FILE).takeIf { it.exists() }?.readText()

    /** The report's text: when, which build and device, and the whole chain of causes. */
    fun report(thread: String, error: Throwable, at: Date): String = buildString {
        appendLine("Lumiere stopped at ${stamp(at, "yyyy-MM-dd HH:mm:ss")}")
        appendLine("Build ${AppBuild.versionName} (${AppBuild.versionCode})${if (AppBuild.quest) ", Quest" else ""}")
        appendLine("Device ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}")
        appendLine("Thread $thread")
        appendLine()
        append(error.stackTraceToString())
    }

    private fun record(context: Context, text: String) {
        File(context.filesDir, FILE).writeText(text)
        val name = "crash-${stamp(Date(), "yyyyMMdd-HHmmss")}.txt"
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/Lumiere")
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return
            context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
        } else {
            context.getExternalFilesDir(null)?.resolve(name)?.writeText(text)
        }
    }

    private fun stamp(at: Date, pattern: String) = SimpleDateFormat(pattern, Locale.US).format(at)
}

/**
 * A breaker for a start that keeps failing. Each start is counted until it
 * has run [SETTLE_MS] or is closed normally; if the last [TRIPS] starts
 * all stopped before then, this one is told to start plainly, without the
 * extras (on the Quest: the cinema, the controllers as a remote, thumb
 * gestures), so the app opens at all. A start that settles resets the count,
 * and the next one tries everything again.
 */
object StartGuard {
    const val SETTLE_MS = 20_000L
    const val TRIPS = 2

    /** Count this start; true when it should leave the extras out. */
    fun begin(context: Context): Boolean {
        val prefs = prefs(context)
        val unsettled = prefs.getInt("unsettled", 0)
        // commit, not apply: a crash a moment later must not lose the count.
        prefs.edit().putInt("unsettled", unsettled + 1).commit()
        return plain(unsettled)
    }

    fun settled(context: Context) { prefs(context).edit().putInt("unsettled", 0).apply() }

    /** Whether a start after [unsettled] failed ones should be a plain one. */
    fun plain(unsettled: Int) = unsettled >= TRIPS

    private fun prefs(context: Context) = context.getSharedPreferences("start", Context.MODE_PRIVATE)
}
