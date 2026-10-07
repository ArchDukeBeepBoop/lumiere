package app.lumiere.android.downloads

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import androidx.compose.runtime.mutableStateListOf
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.parseItem
import org.json.JSONObject
import java.io.File

/** One saved title: its file, and the item as the server described it, for offline. */
data class Download(val id: String, val systemId: Long, val file: File, val item: Item)

/**
 * Titles saved to the phone, to watch with no server in reach. The system's
 * DownloadManager does the transfer, so it survives the app being closed and
 * shows its own notification. Files live in the app's own folder: other apps
 * cannot see them, and uninstalling removes them.
 */
class Downloads(private val context: Context) {
    private val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_MOVIES), "lumiere").apply { mkdirs() }
    val all = mutableStateListOf<Download>()

    init { reload() }

    private fun reload() {
        all.clear()
        dir.listFiles { f -> f.name.endsWith(".json") }?.forEach { meta ->
            runCatching {
                val o = JSONObject(meta.readText())
                all += Download(o.getString("id"), o.getLong("system"), File(o.getString("file")),
                    parseItem(o.getJSONObject("item")))
            }
        }
    }

    fun find(id: String): Download? = all.firstOrNull { it.id == id }

    /** The file, once it has finished arriving; null while it is still on the way. */
    fun playable(id: String): File? = find(id)?.takeIf { status(it) == DownloadManager.STATUS_SUCCESSFUL }?.file

    /** Bytes on the phone now, plus what is still to arrive. */
    fun usedBytes(): Long = all.sumOf { d -> maxOf(d.file.length(), expected(d)) }

    private fun expected(d: Download): Long = runCatching {
        manager.query(DownloadManager.Query().setFilterById(d.systemId)).use { c ->
            if (c.moveToFirst()) c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)) else 0L
        }
    }.getOrDefault(0L)

    /**
     * Starts saving a title; false, with a word on screen, when it would go
     * past the space Settings allows downloads.
     */
    fun start(server: Server, userId: String, itemJson: JSONObject, wifiOnly: Boolean): Boolean {
        val item = parseItem(itemJson)
        if (find(item.id) != null) return true
        val cap = app.lumiere.android.Prefs(context).downloadCapGb * 1_000_000_000L
        val size = itemJson.optJSONArray("MediaSources")?.optJSONObject(0)?.optLong("Size") ?: 0L
        if (cap > 0 && usedBytes() + size > cap) {
            android.widget.Toast.makeText(context, "${item.name} would go past the ${cap / 1_000_000_000} GB downloads may use " +
                "(Settings › Space downloads may use).", android.widget.Toast.LENGTH_LONG).show()
            return false
        }
        val ext = itemJson.optString("Container").substringBefore(',').ifEmpty { "mkv" }
        val file = File(dir, "${item.id}.$ext")
        val request = DownloadManager.Request(Uri.parse(server.streamUrl(item.id, item.mediaSourceId)))
            .addRequestHeader("Authorization", server.authorization())
            .setTitle(item.seriesName?.let { "$it · ${item.name}" } ?: item.name)
            .setDescription("Lumiere")
            .setDestinationUri(Uri.fromFile(file))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedOverMetered(!wifiOnly)
            .setAllowedOverRoaming(false)
        val systemId = manager.enqueue(request)
        File(dir, "${item.id}.json").writeText(
            JSONObject().put("id", item.id).put("system", systemId).put("file", file.path).put("item", itemJson).toString()
        )
        all += Download(item.id, systemId, file, item)
        return true
    }

    fun remove(id: String) {
        val d = find(id) ?: return
        manager.remove(d.systemId)
        d.file.delete()
        File(dir, "$id.json").delete()
        all.remove(d)
    }

    fun status(d: Download): Int = manager.query(DownloadManager.Query().setFilterById(d.systemId)).use { c ->
        if (c.moveToFirst()) c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
        // Gone from the system's list but the file is whole: finished long ago.
        else if (d.file.exists() && d.file.length() > 0) DownloadManager.STATUS_SUCCESSFUL else DownloadManager.STATUS_FAILED
    }

    /** 0–1 while arriving. */
    fun progress(d: Download): Float = manager.query(DownloadManager.Query().setFilterById(d.systemId)).use { c ->
        if (!c.moveToFirst()) return 1f
        val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
        val done = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
        if (total > 0) done.toFloat() / total else 0f
    }
}
