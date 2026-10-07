package app.lumiere.android.api

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class ServerError(message: String) : IOException(message)

/**
 * The Lumiere server, spoken to the way the Mac app speaks to it: Jellyfin's
 * routes and its `MediaBrowser` authorization header. Every call is a suspend
 * function on the IO dispatcher.
 */
class Server(val baseUrl: String, private val deviceId: String, var token: String? = null) {

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().header("Authorization", authorization()).build())
        }
        .build()

    /** The header every request carries, the token included once signed in. */
    fun authorization(): String {
        val device = Build.MODEL.replace("\"", "")
        val pairs = mutableListOf(
            "Client=\"Lumiere Android\"", "Device=\"$device\"",
            "DeviceId=\"$deviceId\"", "Version=\"0.1.0\"",
        )
        token?.let { pairs += "Token=\"$it\"" }
        return "MediaBrowser " + pairs.joinToString(", ")
    }

    fun url(path: String, query: Map<String, String?> = emptyMap()): HttpUrl {
        val builder = baseUrl.trimEnd('/').toHttpUrl().newBuilder()
        path.trim('/').split('/').forEach { builder.addPathSegment(it) }
        query.forEach { (k, v) -> if (v != null) builder.addQueryParameter(k, v) }
        return builder.build()
    }

    suspend fun get(path: String, query: Map<String, String?> = emptyMap()): String {
        val u = url(path, query)
        val key = SnapshotCache.key(u.toString())
        // From the saved copy only, when asked: Home drawn instantly on open.
        if (kotlin.coroutines.coroutineContext[CacheOnly.Key] != null) {
            return SnapshotCache.read(key) ?: throw ServerError("not saved")
        }
        val body = call(Request.Builder().url(u).build())
        if (SnapshotCache.keeps(path)) SnapshotCache.write(key, body)
        return body
    }

    suspend fun post(path: String, body: JSONObject? = null, query: Map<String, String?> = emptyMap()): String {
        val content = (body?.toString() ?: "").toRequestBody("application/json".toMediaType())
        return call(Request.Builder().url(url(path, query)).post(content).build())
    }

    suspend fun delete(path: String): String = call(Request.Builder().url(url(path)).delete().build())

    suspend fun postText(path: String, text: String): String =
        call(Request.Builder().url(url(path)).post(text.toRequestBody("text/plain".toMediaType())).build())

    internal suspend fun call(request: Request): String = withContext(Dispatchers.IO) {
        http.newCall(request).execute().use { response ->
            val text = response.body?.string() ?: ""
            if (!response.isSuccessful) {
                throw ServerError(
                    when (response.code) {
                        401 -> "Wrong user name or password, or signed out."
                        403 -> "The server refused this device. Is it on the same home network?"
                        else -> "The server answered ${response.code}."
                    }
                )
            }
            text
        }
    }

    // MARK: sign-in

    suspend fun publicInfo(): JSONObject = JSONObject(get("System/Info/Public"))

    suspend fun signIn(user: String, password: String): Session {
        val reply = JSONObject(post("Users/AuthenticateByName", JSONObject().put("Username", user).put("Pw", password)))
        val token = reply.getString("AccessToken")
        val u = reply.getJSONObject("User")
        this.token = token
        val name = runCatching { publicInfo().optString("ServerName") }.getOrDefault("Lumiere")
        return Session(baseUrl, u.getString("Id"), u.optString("Name"), token, name)
    }

    // MARK: browsing

    suspend fun views(userId: String) = parseItems(get("UserViews", mapOf("userId" to userId)))

    suspend fun resume(userId: String) = parseItems(
        get("UserItems/Resume", mapOf("userId" to userId, "MediaTypes" to "Video", "Limit" to "24", "Fields" to FIELDS))
    )

    suspend fun nextUp(userId: String) = parseItems(
        get("Shows/NextUp", mapOf("userId" to userId, "Limit" to "24", "Fields" to FIELDS))
    )

    suspend fun latest(userId: String, parentId: String) = parseItems(
        get("Items/Latest", mapOf("userId" to userId, "ParentId" to parentId, "Limit" to "24", "Fields" to FIELDS))
    )

    suspend fun library(userId: String, parentId: String, start: Int, limit: Int, sortBy: String = "SortName",
                        descending: Boolean = false, search: String? = null) = parseItems(
        get(
            "Items", mapOf(
                "userId" to userId, "ParentId" to parentId, "Recursive" to "true",
                "IncludeItemTypes" to "Movie,Series,Video,BoxSet", "SortBy" to sortBy,
                "SortOrder" to if (descending) "Descending" else "Ascending",
                "StartIndex" to "$start", "Limit" to "$limit", "Fields" to FIELDS,
                "ExcludeExtras" to "true", "SearchTerm" to search,
            )
        )
    )

    suspend fun search(userId: String, term: String) = parseItems(
        get(
            "Items", mapOf(
                "userId" to userId, "Recursive" to "true", "SearchTerm" to term, "Limit" to "40",
                "IncludeItemTypes" to "Movie,Series,Episode,Video,MusicAlbum,Audio", "Fields" to FIELDS,
            )
        )
    )

    suspend fun item(userId: String, id: String) = parseItem(JSONObject(get("Users/$userId/Items/$id")))

    suspend fun seasons(userId: String, seriesId: String) =
        parseItems(get("Shows/$seriesId/Seasons", mapOf("userId" to userId)))

    suspend fun episodes(userId: String, seriesId: String, seasonId: String?) = parseItems(
        get("Shows/$seriesId/Episodes", mapOf("userId" to userId, "SeasonId" to seasonId, "Fields" to FIELDS))
    )

    suspend fun children(userId: String, parentId: String) = parseItems(
        get("Items", mapOf("userId" to userId, "ParentId" to parentId, "SortBy" to "SortName", "Fields" to FIELDS))
    )

    suspend fun segments(itemId: String): List<Segment> =
        runCatching { parseSegments(get("MediaSegments/$itemId")) }.getOrDefault(emptyList())

    suspend fun setPlayed(itemId: String, played: Boolean) {
        val request = Request.Builder().url(url("UserPlayedItems/$itemId"))
        if (played) request.post("".toRequestBody()) else request.delete()
        call(request.build())
    }

    // MARK: playback

    fun streamUrl(itemId: String, mediaSourceId: String?): String =
        url("Videos/$itemId/stream", mapOf("static" to "true", "MediaSourceId" to (mediaSourceId ?: itemId))).toString()

    fun subtitleUrl(itemId: String, mediaSourceId: String?, index: Int, codec: String?): String {
        val ext = when (codec?.lowercase()) { "subrip", "srt" -> "srt"; "ass", "ssa" -> "ass"; else -> codec ?: "srt" }
        return url("Videos/$itemId/${mediaSourceId ?: itemId}/Subtitles/$index/Stream.$ext").toString()
    }

    suspend fun report(path: String, itemId: String, positionTicks: Long, sessionId: String, paused: Boolean) {
        runCatching {
            post(
                path, JSONObject()
                    .put("ItemId", itemId).put("MediaSourceId", itemId)
                    .put("PositionTicks", positionTicks).put("PlaySessionId", sessionId)
                    .put("IsPaused", paused).put("CanSeek", true)
            )
        }
    }

    /** An image URL; images need the token too, which the image loader adds. */
    fun imageUrl(itemId: String, kind: String, tag: String?, maxWidth: Int): String =
        url("Items/$itemId/Images/$kind", mapOf("tag" to tag, "maxWidth" to "${app.lumiere.android.Device.artWidth(maxWidth)}",
            "quality" to if (app.lumiere.android.Device.lowMemory) "80" else "85")).toString()

    companion object {
        const val FIELDS = "Overview,Genres,MediaSources,MediaStreams,Chapters,ParentId,DateCreated"
    }
}

/** Run Home's loads against the saved copies, not the network. See SnapshotCache. */
// Its key is a separate object: an object cannot pass itself to its own
// constructor (it is still null then), which failed Home on first load.
object CacheOnly : kotlin.coroutines.AbstractCoroutineContextElement(CacheOnly.Key) {
    object Key : kotlin.coroutines.CoroutineContext.Key<CacheOnly>
}

/**
 * The last answers Home was built from, kept on disk so the next open draws
 * Home at once — tvOS restores an app's last screen the same way — and then
 * refreshes it. Only Home's own questions, and only in the app's private
 * storage.
 */
object SnapshotCache {
    var dir: java.io.File? = null
    private val kept = listOf("UserViews", "UserItems/Resume", "Shows/NextUp", "Items/Latest", "Lumiere/Private")

    fun keeps(path: String) = path in kept

    fun key(url: String) = java.security.MessageDigest.getInstance("SHA-1").digest(url.toByteArray())
        .joinToString("") { "%02x".format(it) }

    fun read(key: String): String? = dir?.resolve(key)?.takeIf { it.exists() }?.readText()

    fun write(key: String, body: String) {
        if (body.length > 400_000) return
        runCatching { dir?.mkdirs(); dir?.resolve(key)?.writeText(body) }
    }

    fun clear() { dir?.deleteRecursively() }
}
