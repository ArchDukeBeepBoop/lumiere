package app.lumiere.android

import android.os.Build
import android.os.Process
import app.lumiere.android.api.Server
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What the app has been doing, sent to the Mac's server log on request — the
 * only way to see inside a projector the Mac cannot reach over USB. Notes the
 * app makes itself, plus this app's own system log; nothing from other apps,
 * and no titles from a private library (the notes never name them).
 */
object Diagnostics {
    private val notes = ArrayDeque<String>()
    private val clock = SimpleDateFormat("HH:mm:ss", Locale.ROOT)

    @Synchronized
    fun note(message: String) {
        notes.addLast("${clock.format(Date())} $message")
        while (notes.size > 200) notes.removeFirst()
    }

    @Synchronized
    private fun noted(): List<String> = notes.toList()

    /** How the private room stands — counts only, never names. Set by the activity. */
    var privacy: () -> String = { "privacy unknown" }

    fun report(): String {
        val head = listOf(
            "device ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "app ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            "memory ${Runtime.getRuntime().maxMemory() / 1_048_576} MB heap allowed, " +
                "${(Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()) / 1_048_576} MB in use, " +
                "${android.os.Debug.getNativeHeapAllocatedSize() / 1_048_576} MB native (pictures and video), " +
                "device ${Device.totalMb} MB${if (Device.lowMemory) ", low-memory mode" else ""}",
            "pictures cached ${imageCacheMb()} MB, reduce motion ${Motion.reduced}",
            privacy(),
        )
        val log = runCatching {
            ProcessBuilder("logcat", "-d", "-t", "300", "--pid=${Process.myPid()}", "*:W")
                .redirectErrorStream(true).start().inputStream.bufferedReader().readText()
        }.getOrDefault("(no system log)")
        return (head + listOf("-- notes --") + noted() + listOf("-- log --") + log.lines().takeLast(300))
            .joinToString("\n")
    }

    /** Set by the activity: the picture cache's size now, for the report. */
    var imageCacheMb: () -> Long = { 0 }

    suspend fun send(server: Server): Boolean = runCatching { server.postText("Lumiere/Diagnostics", report()) }.isSuccess
}
