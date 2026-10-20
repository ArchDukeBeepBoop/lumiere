package app.lumiere.android.local

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.LruCache
import android.util.Size
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class PhoneVideo(val uri: String, val name: String, val folder: String, val durationMs: Long, val added: Long)
data class PhoneSong(val uri: String, val title: String, val artist: String, val album: String, val albumId: Long,
                     val track: Int, val durationMs: Long)

/**
 * The phone's own videos and music, read from Android's media catalogue
 * (MediaStore) — the library On This Phone shows. Needs the media permissions.
 */
object MediaLibrary {
    fun permissions(): Array<String> = if (Build.VERSION.SDK_INT >= 33)
        arrayOf(Manifest.permission.READ_MEDIA_VIDEO, Manifest.permission.READ_MEDIA_AUDIO)
        else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)

    fun allowed(context: Context) = permissions().all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    suspend fun videos(context: Context): List<PhoneVideo> = withContext(Dispatchers.IO) {
        val base = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val cols = arrayOf(MediaStore.Video.Media._ID, MediaStore.Video.Media.DISPLAY_NAME, MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Video.Media.DURATION, MediaStore.Video.Media.DATE_ADDED)
        runCatching {
            context.contentResolver.query(base, cols, null, null, "${MediaStore.Video.Media.DATE_ADDED} DESC")?.use { c ->
                buildList {
                    while (c.moveToNext()) add(PhoneVideo(ContentUris.withAppendedId(base, c.getLong(0)).toString(), c.getString(1) ?: "Video",
                        c.getString(2) ?: "Videos", c.getLong(3), c.getLong(4)))
                }
            }
        }.getOrNull().orEmpty()
    }

    suspend fun songs(context: Context): List<PhoneSong> = withContext(Dispatchers.IO) {
        val base = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val cols = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.ALBUM_ID, MediaStore.Audio.Media.TRACK, MediaStore.Audio.Media.DURATION)
        runCatching {
            context.contentResolver.query(base, cols, "${MediaStore.Audio.Media.IS_MUSIC} != 0", null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE")?.use { c ->
                buildList {
                    while (c.moveToNext()) add(PhoneSong(ContentUris.withAppendedId(base, c.getLong(0)).toString(), c.getString(1) ?: "Song",
                        c.getString(2)?.takeIf { it != "<unknown>" } ?: "Unknown Artist", c.getString(3) ?: "Unknown Album",
                        c.getLong(4), c.getInt(5) % 1000, c.getLong(6)))
                }
            }
        }.getOrNull().orEmpty()
    }

    private val thumbs = LruCache<String, Bitmap>(120)

    /** A video's frame or an album's cover, small, cached. */
    suspend fun thumbnail(context: Context, uri: String, size: Int = 320): Bitmap? = thumbs.get(uri) ?: withContext(Dispatchers.IO) {
        if (Build.VERSION.SDK_INT < 29) return@withContext null
        runCatching { context.contentResolver.loadThumbnail(Uri.parse(uri), Size(size, size), null) }.getOrNull()?.also { thumbs.put(uri, it) }
    }

    /** An album's cover, taken from its first song. */
    fun albumKey(songs: List<PhoneSong>, albumId: Long) = songs.firstOrNull { it.albumId == albumId }?.uri
}
