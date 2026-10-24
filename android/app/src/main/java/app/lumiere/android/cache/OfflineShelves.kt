package app.lumiere.android.cache

import app.lumiere.android.api.Item

/**
 * Continue and Up Next built from what is on the device, for when the Mac
 * does not answer: the downloads, as the [WatchLedger] last left them. Pure,
 * so the order is tested without a device.
 */
object OfflineShelves {

    /** Started and unfinished, most recently watched first. */
    fun resume(items: List<Item>, lastWatched: (String) -> Long): List<Item> =
        items.filter { it.positionTicks > 0 && !it.played }.sortedByDescending { lastWatched(it.id) }

    /**
     * For each show with a watched episode on the device, the next one on the
     * device after the furthest watched — unless one is part-way, which
     * [resume] already offers. Shows watched most recently come first.
     */
    fun upNext(items: List<Item>, lastWatched: (String) -> Long): List<Item> =
        items.filter { it.isEpisode && it.seriesId != null }
            .groupBy { it.seriesId!! }
            .mapNotNull { (_, episodes) ->
                if (episodes.any { it.positionTicks > 0 && !it.played }) return@mapNotNull null
                val ordered = episodes.sortedWith(compareBy({ it.parentIndexNumber ?: 0 }, { it.indexNumber ?: 0 }))
                val furthest = ordered.indexOfLast { it.played }
                if (furthest < 0) return@mapNotNull null
                ordered.drop(furthest + 1).firstOrNull { !it.played }
                    ?.let { next -> next to (episodes.maxOfOrNull { lastWatched(it.id) } ?: 0L) }
            }
            .sortedByDescending { it.second }
            .map { it.first }
}
