package app.lumiere.android.cache

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.lumiere.android.api.Server
import app.lumiere.android.api.ServerError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Fills [LibraryCache] once, then keeps it current from the server's change
 * feed: one request held open, answered the moment something is added,
 * changed or removed. Runs while the app is on screen; the token it keeps
 * means a return to the app catches up with just what changed meanwhile.
 */
class CacheSync(private val cache: LibraryCache) {
    var status by mutableStateOf("")
        private set
    private var job: Job? = null

    fun start(server: Server, userId: String) {
        if (job?.isActive == true) return
        job = CoroutineScope(Dispatchers.IO).launch { run(server, userId) }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    /** Forget the copy: sign-out, or another server. */
    fun forget() {
        stop()
        cache.writableDatabase.execSQL("DELETE FROM item")
        cache.writableDatabase.execSQL("DELETE FROM meta")
    }

    private suspend fun CoroutineScope.run(server: Server, userId: String) {
        var failures = 0
        while (isActive) {
            try {
                val libraries = videoLibraries(server, userId)
                var token = cache.meta("token")?.toLongOrNull() ?: 0
                if (token == 0L) {
                    // The token is taken before the read, so nothing changed
                    // during it is missed.
                    val start = changes(server, 0, 0).getLong("Next")
                    for ((id, name) in libraries) {
                        status = "Saving $name to this phone…"
                        readWhole(server, userId, id)
                    }
                    cache.setMeta("token", start.toString())
                    token = start
                    status = "Up to date"
                }
                val page = changes(server, token, 25)
                failures = 0
                if (page.optBoolean("Reset")) {
                    cache.setMeta("token", null)
                    continue
                }
                apply(server, userId, page, libraries.keys)
                cache.setMeta("token", page.getLong("Next").toString())
                status = "Up to date"
            } catch (e: ServerError) {
                if (e.message?.contains("404") == true) {
                    status = "This server has no change feed"
                    return
                }
                failures++
                status = "Waiting for the server"
                delay(1000L shl failures.coerceAtMost(6))
            } catch (e: java.io.IOException) {
                failures++
                status = "Waiting for the server"
                delay(1000L shl failures.coerceAtMost(6))
            }
        }
    }

    /** The libraries kept here: video ones. Music is read live, as on the Mac. */
    private suspend fun videoLibraries(server: Server, userId: String): Map<String, String> {
        val body = server.get("UserViews", mapOf("userId" to userId))
        cache.setMeta("views", body)
        val array = JSONObject(body).optJSONArray("Items") ?: JSONArray()
        return (0 until array.length()).map { array.getJSONObject(it) }
            .filter { it.optString("CollectionType") !in setOf("music", "playlists", "boxsets") }
            .associate { it.getString("Id") to it.optString("Name") }
    }

    private suspend fun readWhole(server: Server, userId: String, libraryId: String) {
        cache.clearLibrary(libraryId)
        var start = 0
        while (true) {
            val body = JSONObject(server.get("Items", mapOf(
                "userId" to userId, "ParentId" to libraryId, "Recursive" to "true",
                "SortBy" to "SortName", "StartIndex" to "$start", "Limit" to "400", "Fields" to Server.FIELDS,
            )))
            val items = body.optJSONArray("Items") ?: JSONArray()
            cache.upsert((0 until items.length()).map { items.getJSONObject(it) }, libraryId)
            start += items.length()
            if (items.length() < 400) return
        }
    }

    private suspend fun apply(server: Server, userId: String, page: JSONObject, kept: Set<String>) {
        val changed = page.optJSONArray("Changed")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
        val removed = page.optJSONArray("Removed")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
        for (chunk in changed.chunked(100)) {
            val body = JSONObject(server.get("Items", mapOf(
                "userId" to userId, "Ids" to chunk.joinToString(","), "Fields" to Server.FIELDS,
            )))
            val items = body.optJSONArray("Items") ?: JSONArray()
            val wanted = (0 until items.length()).map { items.getJSONObject(it) }
                .filter { it.optString("TopParentId") in kept }
            cache.upsert(wanted)
            // Changed into a library this phone does not keep (or out of one).
            cache.remove(chunk.filter { id -> wanted.none { it.optString("Id") == id } })
        }
        if (removed.isNotEmpty()) cache.remove(removed)
    }

    private suspend fun changes(server: Server, since: Long, wait: Int): JSONObject =
        JSONObject(server.get("Lumiere/Changes", mapOf(
            "since" to "$since", "limit" to "500", "wait" to if (wait > 0) "$wait" else null,
        )))
}
