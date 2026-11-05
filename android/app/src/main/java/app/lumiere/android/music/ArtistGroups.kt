package app.lumiere.android.music

import app.lumiere.android.api.Item

/**
 * One artist as the library should show them: everything credited to them, alone
 * or with guests, under their own name. [item] is the artist shown (named for the
 * primary artist), [ids] every artist entry folded in, and [imageId]/[imageTag]
 * whose picture to draw — their own photo first, then any member's, then an album cover.
 */
data class ArtistGroup(val item: Item, val ids: List<String>, val imageId: String?, val imageTag: String?)

object ArtistGroups {
    /** "feat.", "ft.", "featuring", with or without a bracket, and whatever follows. */
    private val featuring = Regex("""\s*[(\[]?\s*\b(feat|ft|featuring)\b\.?.*$""", RegexOption.IGNORE_CASE)
    /** Where a list of names may be cut: a comma, an ampersand, an " x ", a " with ". */
    private val joins = Regex("""\s*(,|&|\sx\s|\swith\s)\s*""", RegexOption.IGNORE_CASE)

    /** The name with its guests removed; a classical "Composer; performers" keeps the composer. */
    fun lead(name: String): String =
        name.substringBefore(';').replace(featuring, "").trim().trimEnd(',').trim().ifEmpty { name.trim() }

    /**
     * The primary artist's name. A guest list ("Kanye West & JAY-Z") is cut only
     * when the part before the join is an artist in its own right, so a band's own
     * name ("Bob Marley & The Wailers", "Chase & Status") is left whole.
     */
    fun primary(name: String, known: Set<String>): String {
        val l = lead(name)
        for (m in joins.findAll(l)) {
            val head = l.substring(0, m.range.first).trim()
            if (head.isNotEmpty() && head.lowercase() in known) return head
        }
        return l
    }

    fun group(artists: List<Item>): List<ArtistGroup> {
        val known = artists.mapTo(HashSet()) { lead(it.name).lowercase() }
        return artists.groupBy { primary(it.name, known).lowercase() }.map { (key, members) ->
            val own = members.firstOrNull { it.name.trim().lowercase() == key }
            val name = own?.name?.trim() ?: primary(members.first().name, known)
            val face = own?.takeIf { it.primaryTag != null } ?: members.firstOrNull { it.primaryTag != null }
            val cover = (own ?: members.first()).albumId ?: members.firstNotNullOfOrNull { it.albumId }
            val shown = (own ?: members.first()).copy(name = name)
            ArtistGroup(shown, (listOfNotNull(own) + members.filter { it !== own }).map { it.id },
                face?.id ?: cover, face?.primaryTag)
        }.sortedBy { it.item.name.lowercase().removePrefix("the ") }
    }
}
