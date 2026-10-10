package app.lumiere.android.api

import org.json.JSONArray
import org.json.JSONObject

/**
 * Everything the Mac's right-click menu does, in the routes the Mac uses —
 * so a long press on the TV can offer the same.
 */

/** Off Continue Watching: the resume point cleared, the title left unwatched. */
suspend fun Server.hideFromContinueWatching(itemId: String) {
    report("Sessions/Playing/Stopped", itemId, 0, java.util.UUID.randomUUID().toString().replace("-", ""), false)
}

suspend fun Server.refreshMetadata(itemId: String, replaceAll: Boolean) {
    post("Items/$itemId/Refresh", null, mapOf(
        "metadataRefreshMode" to "FullRefresh", "imageRefreshMode" to "FullRefresh",
        "replaceAllMetadata" to "$replaceAll", "replaceAllImages" to "$replaceAll",
    ))
}

/** A frame from the file as the picture: the old one dropped, the server takes a new frame. */
suspend fun Server.useFrameFromFile(itemId: String) {
    runCatching { delete("Items/$itemId/Images/Primary") }
    post("Metadata/Frames")
}

suspend fun Server.removeFromLibrary(itemId: String) { delete("Items/$itemId") }

/** To the Mac's Trash and out of the library. */
suspend fun Server.deleteFile(itemId: String) {
    call(okhttp3.Request.Builder().url(url("Items/$itemId", mapOf("permanent" to "true"))).delete().build())
}

suspend fun Server.addToPlaylist(playlistId: String, ids: List<String>) {
    post("Playlists/$playlistId/Items", null, mapOf("Ids" to ids.joinToString(",")))
}

suspend fun Server.newPlaylist(name: String, ids: List<String>, userId: String) {
    post("Playlists", JSONObject().put("Name", name).put("Ids", JSONArray(ids)).put("UserId", userId))
}

suspend fun Server.addToCollection(collectionId: String, ids: List<String>) {
    post("Collections/$collectionId/Items", null, mapOf("Ids" to ids.joinToString(",")))
}

suspend fun Server.newCollection(name: String, ids: List<String>) {
    post("Collections", null, mapOf("Name" to name, "Ids" to ids.joinToString(",")))
}

/** A candidate from the movie database, for Identify. [raw] is posted back as-is to apply it. */
data class Candidate(val name: String, val year: Int?, val overview: String?, val image: String?, val raw: JSONObject)

suspend fun Server.identifySearch(name: String, year: Int?, series: Boolean): List<Candidate> {
    val body = JSONObject().put("SearchInfo", JSONObject().put("Name", name).apply { year?.let { put("Year", it) } })
    val arr = JSONArray(post("Items/RemoteSearch/${if (series) "Series" else "Movie"}", body))
    return (0 until arr.length()).map { arr.getJSONObject(it) }.map {
        Candidate(it.optString("Name"), if (it.has("ProductionYear")) it.optInt("ProductionYear") else null,
            it.optString("Overview").ifEmpty { null }, it.optString("ImageUrl").ifEmpty { null }, it)
    }
}

suspend fun Server.identifyApply(itemId: String, c: Candidate) { post("Items/RemoteSearch/Apply/$itemId", c.raw) }

data class Artwork(val url: String, val width: Int, val provider: String?)

suspend fun Server.remoteArtwork(itemId: String, type: String): List<Artwork> = runCatching {
    val arr = JSONObject(get("Items/$itemId/RemoteImages", mapOf("type" to type, "limit" to "40"))).optJSONArray("Images") ?: JSONArray()
    (0 until arr.length()).map { arr.getJSONObject(it) }.map {
        Artwork(it.optString("Url"), it.optInt("Width"), it.optString("ProviderName").ifEmpty { null })
    }.filter { it.url.isNotEmpty() }
}.getOrDefault(emptyList())

suspend fun Server.applyArtwork(itemId: String, type: String, url: String) {
    post("Items/$itemId/RemoteImages/Download", null, mapOf("type" to type, "imageUrl" to url))
}

suspend fun Server.removeArtwork(itemId: String, type: String) { delete("Items/$itemId/Images/$type") }
