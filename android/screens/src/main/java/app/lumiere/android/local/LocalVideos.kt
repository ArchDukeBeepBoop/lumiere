package app.lumiere.android.local

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import app.lumiere.android.api.Item

/**
 * The videos kept on this device itself — Movies, Download, anything copied
 * onto the headset — as the system's media library lists them. Each plays in
 * the same player and Theater as the server's films, under an id of its own
 * ("local:" and its content address), so nothing is reported to the server.
 */
object LocalVideos {
    const val PREFIX = "local:"

    data class Video(val uri: Uri, val name: String, val folder: String, val durationMs: Long, val sizeBytes: Long, val width: Int, val height: Int)

    /** The permission to read them, by Android version. */
    val PERMISSION: String get() =
        if (android.os.Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_VIDEO" else "android.permission.READ_EXTERNAL_STORAGE"

    fun allowed(context: Context): Boolean = context.checkSelfPermission(PERMISSION) == android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Every video on the device, newest first. */
    fun list(context: Context): List<Video> {
        val out = mutableListOf<Video>()
        val columns = arrayOf(MediaStore.Video.Media._ID, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE, MediaStore.Video.Media.WIDTH, MediaStore.Video.Media.HEIGHT, MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
        runCatching {
            context.contentResolver.query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, columns, null, null,
                "${MediaStore.Video.Media.DATE_ADDED} DESC")?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    out += Video(ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id),
                        c.getString(1) ?: "Video", c.getString(6) ?: "", c.getLong(2), c.getLong(3), c.getInt(4), c.getInt(5))
                }
            }
        }
        return out
    }

    fun idOf(video: Video): String = PREFIX + video.uri

    fun isLocal(id: String): Boolean = id.startsWith(PREFIX)

    fun uriOf(id: String): Uri = Uri.parse(id.removePrefix(PREFIX))

    /** A stand-in for the server's item, for the player: its name (without the extension), its length. */
    fun itemFor(context: Context, id: String): Item {
        val uri = uriOf(id)
        val v = list(context).firstOrNull { it.uri == uri }
        val name = (v?.name ?: uri.lastPathSegment ?: "Video").substringBeforeLast('.')
        return Item(id = id, name = name, type = "Video", runtimeTicks = v?.durationMs?.times(10_000),
            path = v?.name, streams = if (v != null && v.width > 0) listOf(app.lumiere.android.api.MediaStream(
                index = 0, type = "Video", language = null, title = null, codec = null, isDefault = true, isExternal = false,
                width = v.width, height = v.height)) else emptyList())
    }
}
