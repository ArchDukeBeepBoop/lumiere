package app.lumiere.android

/**
 * The private libraries in this account's own spelling of their ids. The
 * Mac keeps its list on the server; an id written another way there (with
 * dashes, or in capitals) matched none of the libraries here, so the room
 * stood empty and the private titles stayed in the main room. Pure, so it's
 * tested.
 */
object RoomLibraries {
    fun same(a: String, b: String): Boolean = a.replace("-", "").equals(b.replace("-", ""), ignoreCase = true)

    /** [private] as [viewIds] spell them; an id with no match here is kept as it is. */
    fun match(private: Set<String>, viewIds: List<String>): Set<String> =
        if (viewIds.isEmpty() || private.isEmpty()) private
        else private.map { id -> viewIds.firstOrNull { same(it, id) } ?: id }.toSet()
}
