package app.lumiere.android.tv.browse

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** How a row draws its cards (spec §8). The pivot is the same for every kind. */
enum class CardType { Landscape, Portrait, Circle }

/** One card's worth of a title, as the browse screen needs it — nothing server-shaped. */
data class BrowseItem(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    /** "PG-13 · 2021 · Drama · 1h 52m" — one line under the hero's title. */
    val meta: String? = null,
    val synopsis: String? = null,
    /** Card art for this row's card type; null draws the local placeholder. */
    val cardArt: String? = null,
    /** The hero's backdrop; null draws the local placeholder. */
    val backdrop: String? = null,
    val logo: String? = null,
    /** 0..1 for Continue Watching; null otherwise. */
    val progress: Float? = null,
    /** Seed for the placeholder's colour, so each fake card looks its own. */
    val hue: Float = 0f,
)

data class BrowseRow(
    val id: String,
    val title: String,
    val cardType: CardType,
    val items: List<BrowseItem>,
    /** Continue Watching keeps its titles and progress showing on every card (spec §7). */
    val alwaysShowTitle: Boolean = false,
)

/** Where rows come from: the sample catalog now, the Lumiere server after review (spec §10). */
interface Catalog {
    suspend fun rows(): List<BrowseRow>
}

/**
 * Six rows of fifteen, mixing card kinds, with no network and no real titles —
 * art is drawn locally from each item's hue (spec §10, step 1).
 */
object FakeCatalog : Catalog {
    private val names = listOf("Northern Lights", "The Quiet Year", "Paper Harbour", "Glass Orchard", "Low Tide",
        "Signal Fires", "Saltwater", "The Long Room", "Copper Sky", "Field Notes", "Winter Line", "Open Water",
        "Night Ferry", "Small Hours", "Blue Hour")
    private val genres = listOf("Drama", "Comedy", "Thriller", "Documentary", "Sci-Fi", "Animation")

    private fun item(row: Int, i: Int, progress: Float? = null) = BrowseItem(
        id = "fake-$row-$i",
        title = names[i % names.size],
        subtitle = if (row == 2) "S1 · E${i + 1}" else "${2010 + (i * 3 + row) % 15}",
        meta = listOf(listOf("PG", "PG-13", "R", "TV-14")[(i + row) % 4], "${2010 + (i * 3 + row) % 15}",
            genres[(i + row) % genres.size], "${1 + i % 2}h ${(i * 7) % 60}m").joinToString(" · "),
        synopsis = "A sample title for reviewing the browse screen. Its art is drawn on the device, " +
            "and nothing here comes from the Mac's library.",
        progress = progress,
        hue = ((row * 47 + i * 23) % 360).toFloat(),
    )

    override suspend fun rows(): List<BrowseRow> = listOf(
        BrowseRow("top", "Top Picks", CardType.Landscape, List(15) { item(0, it) }),
        BrowseRow("apps", "Libraries", CardType.Circle, List(15) { item(1, it) }),
        BrowseRow("continue", "Continue Watching", CardType.Landscape, List(15) { item(2, it, progress = (it % 9 + 1) / 10f) },
            alwaysShowTitle = true),
        BrowseRow("films", "Films", CardType.Portrait, List(15) { item(3, it) }),
        BrowseRow("shows", "Shows", CardType.Portrait, List(15) { item(4, it) }),
        BrowseRow("new", "Recently Added", CardType.Landscape, List(15) { item(5, it) }),
    )
}

/** What the screen remembers about focus (spec §2). */
class BrowseState {
    var focusedRow by mutableIntStateOf(0)
    val focusedIndexPerRow = mutableStateMapOf<Int, Int>()
    /** The Row 0 card the hero shows, settled after the debounce. */
    var heroItem by mutableStateOf<BrowseItem?>(null)
}
