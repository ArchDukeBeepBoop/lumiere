package app.lumiere.android.api

import org.json.JSONObject

/** Everything the richer screens ask for, in the routes the Mac uses. */

private const val GRID = "Movie,Series,Video,BoxSet"

suspend fun Server.similar(userId: String, id: String) = parseItems(
    get("Items/$id/Similar", mapOf("userId" to userId, "Limit" to "16", "Fields" to Server.FIELDS))
)

suspend fun Server.extras(userId: String, id: String) = runCatching {
    parseItems(get("Users/$userId/Items/$id/SpecialFeatures"))
}.getOrDefault(emptyList())

suspend fun Server.genres(userId: String, parentId: String): List<String> = runCatching {
    parseItems(get("Genres", mapOf("userId" to userId, "ParentId" to parentId))).map { it.name }
}.getOrDefault(emptyList())

/** A library page with the grid's filters: genre, unwatched, favourites, and the A–Z jump. */
suspend fun Server.libraryPage(
    userId: String, parentId: String?, start: Int, limit: Int, sortBy: String, descending: Boolean,
    genre: String? = null, unwatched: Boolean = false, favourites: Boolean = false, from: String? = null,
    types: String = GRID, personId: String? = null,
) = parseItems(
    get("Items", mapOf(
        "userId" to userId, "ParentId" to parentId, "Recursive" to "true", "IncludeItemTypes" to types,
        "SortBy" to sortBy, "SortOrder" to if (descending) "Descending" else "Ascending",
        "StartIndex" to "$start", "Limit" to "$limit", "Fields" to Server.FIELDS, "ExcludeExtras" to "true",
        "Genres" to genre, "NameStartsWithOrGreater" to from, "PersonIds" to personId,
        "Filters" to listOfNotNull(if (unwatched) "IsUnplayed" else null, if (favourites) "IsFavorite" else null)
            .joinToString(",").ifEmpty { null },
    ))
)

suspend fun Server.favourites(userId: String) = libraryPage(userId, null, 0, 60, "SortName", false,
    favourites = true, types = "Movie,Series,Episode,Video,MusicAlbum")

suspend fun Server.collections(userId: String) = libraryPage(userId, null, 0, 300, "SortName", false, types = "BoxSet")

/** What was finished most recently — the Mac's Watched Lately row. */
suspend fun Server.watchedLately(userId: String) = parseItems(
    get("Items", mapOf(
        "userId" to userId, "Recursive" to "true", "IncludeItemTypes" to "Movie,Episode,Video",
        "Filters" to "IsPlayed", "SortBy" to "DatePlayed", "SortOrder" to "Descending", "Limit" to "20",
        "Fields" to Server.FIELDS,
    ))
)

suspend fun Server.playlists(userId: String) = parseItems(
    get("Items", mapOf("userId" to userId, "Recursive" to "true", "IncludeItemTypes" to "Playlist", "SortBy" to "SortName"))
)

suspend fun Server.playlistItems(userId: String, id: String) =
    parseItems(get("Playlists/$id/Items", mapOf("userId" to userId, "Fields" to Server.FIELDS)))

suspend fun Server.people(term: String) = runCatching {
    parseItems(get("Persons", mapOf("searchTerm" to term, "Limit" to "8")))
}.getOrDefault(emptyList())

/** Trickplay sheets for the scrub preview: width, tile grid, interval, count. */
data class Trickplay(val width: Int, val height: Int, val tiles: Int, val intervalMs: Int, val count: Int)

suspend fun Server.trickplay(userId: String, id: String): Trickplay? = runCatching {
    val o = JSONObject(get("Users/$userId/Items/$id", mapOf("Fields" to "Trickplay"))).optJSONObject("Trickplay")
        ?: return null
    val bySource = o.optJSONObject(o.keys().next()) ?: return null
    val info = bySource.optJSONObject(bySource.keys().next()) ?: return null
    Trickplay(info.optInt("Width"), info.optInt("Height"), info.optInt("TileWidth"), info.optInt("Interval"),
        info.optInt("ThumbnailCount"))
}.getOrNull()

fun Server.trickplaySheet(id: String, width: Int, sheet: Int) =
    url("Videos/$id/Trickplay/$width/$sheet.jpg").toString()

fun Server.personImage(id: String, tag: String?) = imageUrl(id, "Primary", tag, 240)

/** The ten best rated of a kind, as the Mac's Top 10 rows: by community rating. */
suspend fun Server.topRated(userId: String, parentId: String?, types: String) = runCatching {
    libraryPage(userId, parentId, 0, 10, "CommunityRating", true, types = types)
}.getOrDefault(emptyList())

/** Every film and show genre, for the genre row. */
suspend fun Server.allGenres(userId: String): List<String> = runCatching {
    parseItems(get("Genres", mapOf("userId" to userId))).map { it.name }
}.getOrDefault(emptyList())

/** One title with a backdrop from a genre or library, to picture its card. */
suspend fun Server.pictureFor(userId: String, parentId: String?, genre: String?): Item? = runCatching {
    libraryPage(userId, parentId, 0, 6, "Random", false, genre = genre).firstOrNull { it.backdropTag != null }
}.getOrNull()

suspend fun Server.clientSettings(): JSONObject? = runCatching { JSONObject(get("Lumiere/ClientSettings")) }.getOrNull()
suspend fun Server.saveClientSettings(o: JSONObject) { runCatching { post("Lumiere/ClientSettings", o) } }

/** Held Play: something at random from what is selected — an episode of a show, a title of a library, else itself. */
suspend fun Server.shuffleFrom(userId: String, target: Item): Item? = when {
    target.isPlayable -> target
    else -> parseItems(get("Items", mapOf("userId" to userId, "parentId" to (target.seriesId ?: target.id), "recursive" to "true",
        "includeItemTypes" to "Movie,Episode", "sortBy" to "Random", "limit" to "1"))).firstOrNull()
}

/** Titles by id, in the order asked. */
suspend fun Server.byIds(userId: String, ids: List<String>): List<Item> = if (ids.isEmpty()) emptyList() else
    parseItems(get("Items", mapOf("userId" to userId, "Ids" to ids.joinToString(","), "Fields" to Server.FIELDS)))
        .sortedBy { ids.indexOf(it.id) }

/** A long request: subtitle downloads and syncing take the server minutes, past the usual 30 seconds. */
private suspend fun Server.slowPost(path: String, query: Map<String, String?> = emptyMap()): String =
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        http.newBuilder().readTimeout(6, java.util.concurrent.TimeUnit.MINUTES).build()
            .newCall(okhttp3.Request.Builder().url(url(path, query)).post(ByteArray(0).let { okhttp3.RequestBody.create(null, it) }).build())
            .execute().use { r -> if (!r.isSuccessful) error("the server answered ${r.code}"); r.body?.string().orEmpty() }
    }

/** Finds the best subtitle in [language] for a title with none, saves it beside the file and fits its timing. */
suspend fun Server.findSubtitle(itemId: String, language: String): String? {
    val found = JSONObject(get("Items/$itemId/RemoteSubtitles", mapOf("language" to language))).optJSONArray("Results") ?: return null
    if (found.length() == 0) return null
    // Trusted, human-made, most downloaded first: the list the server gives is already ranked.
    val pick = (0 until found.length()).map { found.getJSONObject(it) }
        .firstOrNull { !it.optBoolean("MachineTranslated") && !it.optBoolean("AiTranslated") } ?: found.getJSONObject(0)
    slowPost("Items/$itemId/RemoteSubtitles/${pick.getInt("FileId")}", mapOf("sync" to "true"))
    return pick.optString("Release").ifEmpty { "a subtitle" }
}

/** Fits every subtitle file beside a title to its dialogue; how many moved. */
suspend fun Server.syncSubtitles(item: Item): Int = item.streams.filter { it.type == "Subtitle" && it.isExternal }.count { st ->
    runCatching { slowPost("Items/${item.id}/Subtitles/${st.index}/Sync") }.isSuccess
}
