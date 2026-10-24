package app.lumiere.android.cache

import android.content.Context
import androidx.compose.runtime.mutableIntStateOf
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Where each title was left and whether it was watched, kept on the device
 * first and sent to the Mac after — so a download carries on where it was
 * stopped, watched marks change with no connection, and nothing is lost:
 * what the Mac has not yet heard is sent again once it answers.
 */
class WatchLedger(context: Context) {
    data class Entry(val ticks: Long, val played: Boolean?, val at: Long, val pending: Boolean)

    private val store = context.getSharedPreferences("lumiere.ledger", Context.MODE_PRIVATE)
    private val lock = Mutex()
    /** Bumped on every change, for screens that show progress. */
    val version = mutableIntStateOf(0)

    fun get(id: String): Entry? = store.getString(id, null)?.let { s ->
        runCatching { JSONObject(s).let { o ->
            Entry(o.optLong("t"), if (o.has("p")) o.getBoolean("p") else null, o.optLong("at"), o.optBoolean("q"))
        } }.getOrNull()
    }

    private fun put(id: String, e: Entry) {
        store.edit().putString(id, JSONObject().put("t", e.ticks).put("at", e.at).put("q", e.pending)
            .apply { e.played?.let { put("p", it) } }.toString()).apply()
        version.intValue++
    }

    /** Where playback is now; [sent] when the Mac already has it. */
    fun position(id: String, ticks: Long, sent: Boolean) {
        val old = get(id)
        put(id, Entry(ticks, old?.played, System.currentTimeMillis(), !sent || (old?.pending == true)))
    }

    /** Watched or not; a watched title starts again from the beginning. */
    fun played(id: String, played: Boolean, sent: Boolean) {
        val old = get(id)
        put(id, Entry(if (played) 0 else old?.ticks ?: 0, played, System.currentTimeMillis(), !sent || (old?.pending == true)))
    }

    /** The item as this device last left it, where that is newer than what the Mac said. */
    fun apply(item: Item, trustServer: Boolean = true): Item {
        val e = get(item.id) ?: return item
        if (trustServer && !e.pending) return item
        val played = e.played ?: item.played
        return item.copy(positionTicks = if (played) 0 else e.ticks, played = played)
    }

    fun apply(items: List<Item>, trustServer: Boolean = true) = items.map { apply(it, trustServer) }

    /** Marks watched, here at once and on the Mac when it can be reached. */
    suspend fun setPlayed(server: Server?, id: String, played: Boolean) {
        val sent = server != null && runCatching { server.setPlayed(id, played) }.isSuccess
        played(id, played, sent)
    }

    /** Sends the Mac everything it has not yet heard; true when nothing is left waiting. */
    suspend fun flush(server: Server): Boolean = lock.withLock {
        withContext(Dispatchers.IO) {
            var all = true
            for (id in store.all.keys.toList()) {
                val e = get(id) ?: continue
                if (!e.pending) continue
                val ok = runCatching {
                    if (e.played != null) server.setPlayed(id, e.played)
                    if (e.played != true) check(server.reportStopped(id, e.ticks))
                }.isSuccess
                if (ok) put(id, e.copy(pending = false)) else all = false
            }
            all
        }
    }

    val waiting: Int get() = store.all.keys.count { get(it)?.pending == true }
}
