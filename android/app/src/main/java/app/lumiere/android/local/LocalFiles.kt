package app.lumiere.android.local

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.mutableStateOf

/** A file from the phone the app has played: where it is, its name, video or sound. */
data class LocalEntry(val uri: String, val name: String, val video: Boolean)

/**
 * Videos and songs on the phone itself. They are chosen through Android's
 * own picker (so the app needs no storage permission), kept readable with a
 * lasting grant, and the last few remembered for playing again.
 */
object LocalFiles {
    val recent = mutableStateOf<List<LocalEntry>>(emptyList())

    private fun prefs(context: Context) = context.getSharedPreferences("lumiere.local", Context.MODE_PRIVATE)

    fun load(context: Context) {
        recent.value = prefs(context).getString("recent", "")!!.split('\n').mapNotNull { line ->
            val p = line.split('\t'); if (p.size == 3) LocalEntry(p[0], p[1], p[2] == "v") else null
        }
    }

    /** Remembered, newest first, and kept readable after the phone restarts. */
    fun remember(context: Context, uri: Uri): LocalEntry {
        runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        val entry = LocalEntry(uri.toString(), nameOf(context, uri), context.contentResolver.getType(uri)?.startsWith("audio") != true)
        val list = (listOf(entry) + recent.value.filter { it.uri != entry.uri }).take(20)
        recent.value = list
        prefs(context).edit().putString("recent", list.joinToString("\n") { "${it.uri}\t${it.name.replace('\t', ' ')}\t${if (it.video) "v" else "a"}" }).apply()
        return entry
    }

    fun forget(context: Context) { recent.value = emptyList(); prefs(context).edit().remove("recent").apply() }

    fun nameOf(context: Context, uri: Uri): String = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment?.substringAfterLast('/') ?: "Video"

    /** A video or song handed over by another app ("Open with"), or null. */
    fun fromIntent(context: Context, intent: Intent?): Pair<String, String>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        val type = intent.type ?: context.contentResolver.getType(uri) ?: return null
        if (!type.startsWith("video/") && !type.startsWith("audio/")) return null
        return uri.toString() to nameOf(context, uri)
    }
}
