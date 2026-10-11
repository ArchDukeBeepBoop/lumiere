package app.lumiere.android

import androidx.compose.runtime.mutableStateOf
import app.lumiere.android.api.Item

/**
 * Shows you took off Up Next. Jellyfin's Next Up has no way to dismiss a
 * series, so the device keeps the list itself, one for each account, and
 * Home leaves those shows out. A show comes back by itself the next time you
 * play or finish one of its episodes here. Newest first, at most [MAX], saved
 * as one line of ids; Compose state, so Home redraws the moment it changes.
 */
class UpNextDismissed(val owner: String, saved: String?, private val save: (String) -> Unit) {
    private val ids = mutableStateOf(decode(saved))

    /** The shows taken off, newest first. */
    val shows: List<String> get() = ids.value

    operator fun contains(seriesId: String?): Boolean = seriesId != null && seriesId in ids.value

    fun dismiss(seriesId: String) = put((listOf(seriesId) + ids.value.filter { it != seriesId }).take(MAX))

    /** Puts [seriesId] back on Up Next; false when it wasn't off. */
    fun restore(seriesId: String?): Boolean {
        if (seriesId == null || seriesId !in ids.value) return false
        put(ids.value - seriesId)
        return true
    }

    /** [items] without the shows taken off: an episode goes with its show. */
    fun filter(items: List<Item>): List<Item> = if (ids.value.isEmpty()) items else items.filter { showOf(it) !in ids.value }

    private fun put(v: List<String>) { ids.value = v; save(encode(v)) }

    /**
     * What taking a card off one of Home's rows does: [unlist] takes it off
     * the titles you added to Up Next yourself, [hide] clears its resume point
     * on the server (Continue Watching), and [dismiss] is the show to keep off.
     */
    data class Removal(val unlist: Boolean, val hide: Boolean, val dismiss: String?)

    companion object {
        /** The rows a card can be taken off: Continue Watching and Next Up when apart, Up Next when one. */
        const val CONTINUE = "continue"
        const val NEXT_UP = "nextup"
        const val UP_NEXT = "upnext"
        const val MAX = 100

        /** A row's name, as its title on Home says it. */
        fun rowName(row: String): String = when (row) { CONTINUE -> "Continue Watching"; NEXT_UP -> "Next Up"; else -> "Up Next" }

        /** The show a card stands for: an episode's series, or the title itself. */
        fun showOf(item: Item): String = item.seriesId ?: item.id

        fun encode(ids: List<String>): String = ids.joinToString(",")

        /** A saved line back into ids; nothing saved, or a damaged line, is an empty list. */
        fun decode(raw: String?): List<String> =
            raw.orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(MAX)

        /**
         * Taking [item] off [row]. Continue Watching only forgets where you
         * were; Next Up only keeps the show off; the one Up Next row does all
         * three, as everything in it would otherwise bring the title back.
         */
        fun removal(row: String, item: Item, watchlist: List<String>): Removal {
            val show = if (item.isEpisode) item.seriesId else item.id.takeIf { item.isSeries }
            return when (row) {
                CONTINUE -> Removal(unlist = false, hide = true, dismiss = null)
                NEXT_UP -> Removal(unlist = false, hide = false, dismiss = show)
                else -> Removal(unlist = item.id in watchlist, hide = item.positionTicks > 0, dismiss = show)
            }
        }
    }
}
