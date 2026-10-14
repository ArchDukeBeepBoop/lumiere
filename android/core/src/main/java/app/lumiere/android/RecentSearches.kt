package app.lumiere.android

/**
 * The searches you made lately, newest first, as Netflix and the Apple TV app
 * keep them: the same words in another case are one search, kept where you
 * last typed them and in the case you last used.
 */
object RecentSearches {
    /** How many are kept. */
    const val LIMIT = 8

    /** Your searches with [term] put first; a blank term changes nothing. */
    fun add(list: List<String>, term: String, limit: Int = LIMIT): List<String> {
        val t = term.trim()
        if (t.isEmpty()) return list.take(limit)
        return (listOf(t) + list.filter { !it.trim().equals(t, ignoreCase = true) }).take(limit)
    }

    /**
     * What was saved, one search a line. Earlier versions kept the words
     * untrimmed and could keep two that differed only in case; they load
     * tidied, the newer of each pair kept.
     */
    fun decode(saved: String?): List<String> =
        (saved ?: "").split('\n').map { it.trim() }.filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }.take(LIMIT)

    fun encode(list: List<String>): String = list.joinToString("\n")

    /** The words a speech recogniser heard, its best guess first; null when it heard nothing. */
    fun heard(results: List<String?>?): String? = results?.firstOrNull { !it.isNullOrBlank() }?.trim()
}
