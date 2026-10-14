package app.lumiere.android

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.lumiere.android.api.Item
import app.lumiere.android.api.backOnContinueWatching
import app.lumiere.android.api.hideFromContinueWatching
import app.lumiere.android.api.setFavorite
import kotlinx.coroutines.launch

/**
 * My List, as Netflix and the Apple TV app call it: the server's favourites,
 * on the TV and the Quest. A change shows at once wherever the title is
 * drawn, then goes to the server; if the server refuses it, the title goes
 * back to what the server last had. Pressed again while a change is on its
 * way, the newest choice follows it, so the server always ends where you
 * did. One for each account (AppState.myList); pure apart from Compose
 * state, so it's tested.
 */
class MyList(val owner: String?) {
    /** The server's list as Home last loaded it, kept so Home comes back drawn; null until then. */
    var saved by mutableStateOf<List<Item>?>(null)
        private set

    // [at] when chosen and [settled] when the server answered, both on one count of events.
    private data class Choice(val item: Item, val on: Boolean, val at: Long, val settled: Long? = null)
    // What you see: in the list or not, with the title as it was when chosen.
    private val wanted = mutableStateMapOf<String, Choice>()
    // What the server last confirmed, and the titles with a change on its way.
    private val known = mutableMapOf<String, Boolean>()
    private val sending = mutableSetOf<String>()
    private var count = 0L

    /** Whether [item] is in My List, as you see it now. */
    fun has(item: Item): Boolean = wanted[item.id]?.on ?: item.favorite

    /**
     * Flips [item] at once. Returns what to send to the server, or null when
     * a change to it is already on its way: [sent] then sends this one after.
     */
    fun toggle(item: Item): Boolean? {
        if (item.id !in known) known[item.id] = item.favorite
        val to = !has(item)
        wanted[item.id] = Choice(item, to, ++count)
        return if (sending.add(item.id)) to else null
    }

    /** The server took [value]: what to send next, when you changed it again meanwhile, or null when it's done. */
    fun sent(id: String, value: Boolean): Boolean? {
        known[id] = value
        val want = wanted[id]?.on ?: value
        if (want != value) return want
        sending -= id
        wanted[id]?.let { wanted[id] = it.copy(settled = ++count) }
        return null
    }

    /** The server refused: the title goes back to what it last confirmed. */
    fun failed(id: String) {
        sending -= id
        val back = known[id] ?: return
        wanted[id]?.let { wanted[id] = it.copy(on = back, settled = ++count) }
    }

    /** Where a load of the server's list begins; give it to [loaded] with the answer. */
    fun mark(): Long = count

    /**
     * The server's answer to a load begun at [mark]. Choices the server had
     * settled before it began are the server's to show from now on, so a
     * title taken out on your phone leaves the TV's row too. Any settled
     * since, or still on their way, stay over it: the load may have been
     * answered before the change reached the server.
     */
    fun loaded(list: List<Item>, mark: Long) {
        saved = list
        wanted.filter { (_, c) -> c.settled != null && c.settled <= mark }.keys.forEach { wanted.remove(it); known.remove(it) }
    }

    /** [server]'s list as you see it: what you just added first, newest first, and what you just took out gone. */
    fun over(server: List<Item>): List<Item> {
        if (wanted.isEmpty()) return server
        val there = server.mapTo(HashSet()) { it.id }
        val added = wanted.values.filter { it.on && it.item.id !in there && it.item.type in KINDS }.sortedByDescending { it.at }.map { it.item }
        return added + server.filter { wanted[it.id]?.on != false }
    }

    companion object {
        /** What Home's row holds: films, shows, videos and episodes. Albums stay in Music and Library. */
        val KINDS = setOf("Movie", "Series", "Video", "Episode")
    }
}

/**
 * Puts [item] in My List or takes it out: on screen at once, then on the
 * server. Throws, once it's put back, when the server refuses. The sending
 * isn't stopped by leaving the page that asked, which would leave the list
 * showing what the server never got.
 */
suspend fun AppState.changeMyList(item: Item) {
    val server = server ?: return
    val list = myList
    var next = list.toggle(item) ?: return
    kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
        while (true) {
            try { server.setFavorite(item.id, next) } catch (e: Exception) { list.failed(item.id); throw e }
            next = list.sent(item.id, next) ?: break
        }
    }
}

/**
 * Takes [item] off Home's [row] (see UpNextDismissed.removal): gone from
 * Home at once, the server told behind it, and the notice offers it back.
 */
suspend fun AppState.takeOffRow(item: Item, row: String) {
    val server = server ?: return
    val userId = session?.userId ?: return
    val dismissed = settings.upNextDismissed(userId)
    val r = UpNextDismissed.removal(row, item, settings.watchlist)
    val listedAt = settings.watchlist.indexOf(item.id)
    if (r.unlist) settings.watchlist = settings.watchlist - item.id
    r.dismiss?.let { dismissed.dismiss(it) }
    if (r.hide) { offContinue = offContinue + item.id; server.hideFromContinueWatching(item.id) }
    // Five seconds to take it back, as Apple TV offers: on its own scope, as the
    // panel that asked has gone by the time Menu is pressed.
    undo = "Removed from ${UpNextDismissed.rowName(row)}" to {
        if (r.unlist && item.id !in settings.watchlist)
            settings.watchlist = settings.watchlist.toMutableList().apply { add(listedAt.coerceIn(0, size), item.id) }
        r.dismiss?.let { dismissed.restore(it) }
        if (r.hide) kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main.immediate).launch {
            server.backOnContinueWatching(item.id, item.positionTicks)
            offContinue = offContinue - item.id
            homeRefresh++
        }
    }
}

/**
 * [item] has started playing: a show taken off Up Next comes back with it, and
 * a title taken off Continue Watching may return there.
 */
fun AppState.playing(item: Item) {
    val userId = session?.userId ?: return
    settings.upNextDismissed(userId).restore(item.seriesId)
    if (item.id in offContinue) offContinue = offContinue - item.id
}
