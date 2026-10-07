package app.lumiere.android.api

import org.json.JSONObject

/** One line of lyrics; [start] in seconds when they are synced. */
data class LyricLine(val text: String, val start: Double?)

/** Music, lyrics, favourites and editing — the Mac app's routes, the same shapes. */

suspend fun Server.albums(userId: String, libraryId: String, start: Int, limit: Int, sortBy: String = "SortName",
                          descending: Boolean = false, artistId: String? = null) = parseItems(
    get("Items", mapOf(
        "userId" to userId, "ParentId" to if (artistId == null) libraryId else null, "Recursive" to "true",
        "IncludeItemTypes" to "MusicAlbum", "SortBy" to sortBy, "ArtistIds" to artistId,
        "SortOrder" to if (descending) "Descending" else "Ascending",
        "StartIndex" to "$start", "Limit" to "$limit",
    ))
)

suspend fun Server.artists(userId: String, libraryId: String, start: Int, limit: Int) = parseItems(
    get("Artists/AlbumArtists", mapOf(
        "userId" to userId, "ParentId" to libraryId, "StartIndex" to "$start", "Limit" to "$limit",
        "SortBy" to "SortName",
    ))
)

/** Tracks in a library, an album or by an artist, in the order asked for. */
suspend fun Server.tracks(userId: String, parentId: String?, start: Int, limit: Int, sortBy: List<String>,
                          descending: Boolean = false, artistId: String? = null) = parseItems(
    get("Items", mapOf(
        "userId" to userId, "ParentId" to parentId, "Recursive" to "true", "IncludeItemTypes" to "Audio",
        "SortBy" to sortBy.joinToString(","), "SortOrder" to if (descending) "Descending" else "Ascending",
        "StartIndex" to "$start", "Limit" to "$limit", "ArtistIds" to artistId,
    ))
)

fun Server.audioUrl(itemId: String): String =
    url("Audio/$itemId/universal", mapOf("static" to "true", "MediaSourceId" to itemId)).toString()

suspend fun Server.lyrics(itemId: String): List<LyricLine>? = runCatching {
    parseLyrics(get("Audio/$itemId/Lyrics"))
}.getOrNull()

/** Saved beside the track, as the Mac app's Edit Track does. */
suspend fun Server.saveLyrics(itemId: String, text: String) {
    postText("Audio/$itemId/Lyrics", text)
}

suspend fun Server.setFavorite(itemId: String, favorite: Boolean) {
    if (favorite) post("UserFavoriteItems/$itemId") else delete("UserFavoriteItems/$itemId")
}

/**
 * Jellyfin's edit contract: the whole item, posted back with the edited keys
 * changed. Read fresh first so nothing the screen never loaded is wiped.
 */
suspend fun Server.editItem(userId: String, itemId: String, edits: Map<String, Any?>) {
    val whole = JSONObject(get("Users/$userId/Items/$itemId"))
    edits.forEach { (k, v) -> whole.put(k, v ?: JSONObject.NULL) }
    post("Items/$itemId", whole)
}

/** Jellyfin's lyrics shape: timed lines, or one string of plain text. */
fun parseLyrics(body: String): List<LyricLine>? {
    val o = JSONObject(body)
    val plain = o.opt("Lyrics")
    if (plain is String) return plain.lines().map { LyricLine(it, null) }.ifEmpty { null }
    val array = o.optJSONArray("Lyrics") ?: return null
    return (0 until array.length()).mapNotNull { array.optJSONObject(it) }.map {
        LyricLine(it.optString("Text"), if (it.has("Start")) it.optLong("Start") / TICKS_PER_SECOND.toDouble() else null)
    }.ifEmpty { null }
}

/** The line being sung at [position]: the last that has started. */
fun currentLyric(lines: List<LyricLine>, position: Double): Int? {
    var found: Int? = null
    for ((i, line) in lines.withIndex()) {
        val start = line.start ?: return null
        if (start > position) break
        found = i
    }
    return found
}

/** Back to LRC, so editing synced lyrics keeps their timing. */
fun toLrc(lines: List<LyricLine>): String = lines.joinToString("\n") { line ->
    val start = line.start ?: return@joinToString line.text
    val minutes = (start / 60).toInt()
    "[%02d:%05.2f]%s".format(java.util.Locale.ROOT, minutes, start - minutes * 60, line.text)
}

/** The item exactly as the server sends it, for a download's offline copy. */
suspend fun Server.itemJson(userId: String, id: String): JSONObject = JSONObject(get("Users/$userId/Items/$id"))

/** The Mac's private libraries, kept on the server. */
suspend fun Server.privateLibraries(): Set<String> {
    val a = JSONObject(get("Lumiere/Private")).optJSONArray("Libraries") ?: return emptySet()
    return (0 until a.length()).map { a.optString(it) }.filter { it.isNotEmpty() }.toSet()
}
