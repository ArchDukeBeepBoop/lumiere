package app.lumiere.android.tv

import android.annotation.SuppressLint
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import app.lumiere.android.MainActivity
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import app.lumiere.android.api.TICKS_PER_SECOND
import app.lumiere.android.widget.ResumeWidget

/**
 * The TV's own Play Next row: what is half-watched in Lumiere shows on the
 * Android TV home screen, a press from carrying on. Rewritten whole each time
 * Home reloads. Private titles are never published — the TV's home screen is
 * shared by everyone in the room.
 * [server] is kept for when artwork can be served without a token. Devices without the row (Fire OS) ignore it.
 */
object WatchNext {
    @SuppressLint("RestrictedApi")
    fun publish(context: Context, server: Server, items: List<Item>) {
        runCatching {
            val resolver = context.contentResolver
            resolver.query(TvContractCompat.WatchNextPrograms.CONTENT_URI, null, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val program = WatchNextProgram.fromCursor(c)
                    if (program.internalProviderId?.startsWith("lumiere:") == true) {
                        resolver.delete(TvContractCompat.buildWatchNextProgramUri(program.id), null, null)
                    }
                }
            }
            items.take(10).forEach { item ->
                val open = Intent(context, MainActivity::class.java).setAction(ResumeWidget.OPEN).putExtra("item", item.id)
                val program = WatchNextProgram.Builder()
                    .setType(if (item.isEpisode) TvContractCompat.PreviewPrograms.TYPE_TV_EPISODE else TvContractCompat.PreviewPrograms.TYPE_MOVIE)
                    .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                    .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
                    .setTitle(item.seriesName ?: item.name)
                    .setEpisodeTitle(if (item.isEpisode) item.name else null)
                    .setDescription(item.overview)
                    // No artwork: the launcher would fetch it without a login, and
                    // putting the token in a URL other apps can read is not worth a picture.
                    .setLastPlaybackPositionMillis((item.positionTicks / (TICKS_PER_SECOND / 1000)).toInt())
                    .setDurationMillis(((item.runtimeTicks ?: 0) / (TICKS_PER_SECOND / 1000)).toInt())
                    .setIntentUri(Uri.parse(open.toUri(Intent.URI_INTENT_SCHEME)))
                    .setInternalProviderId("lumiere:${item.id}")
                    .build()
                resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues())
                    ?.let { ContentUris.parseId(it) }
            }
        }
    }
}
