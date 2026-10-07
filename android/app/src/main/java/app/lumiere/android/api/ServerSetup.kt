package app.lumiere.android.api

import org.json.JSONArray
import org.json.JSONObject

/** One place on disk feeding a library. */
data class LibraryFolder(val id: String, val path: String)

/** A library as its owner manages it: name, kind, folders. */
data class ServerLibrary(val id: String, val name: String, val kind: String, val folders: List<LibraryFolder>, val items: Int)

/** A folder on the server's disk, for choosing where a library lives. */
data class FolderEntry(val name: String, val path: String)

/** The kinds a library can declare, as the Mac offers them. */
enum class LibraryKind(val raw: String, val title: String, val note: String) {
    Movies("movies", "Films", "One film per file or folder. Posters, cast and collections are looked up."),
    Shows("tvshows", "TV Shows & Anime", "A folder per show, seasons inside. Episodes are matched and named."),
    Music("music", "Music", "Albums and artists from the files' tags, with lyrics."),
    HomeVideos("homevideos", "Home Videos", "Your own clips, named by their files. Nothing is looked up."),
    Mixed("mixed", "Mixed", "Films and shows side by side."),
    Folders("", "Plain Folders", "Browse the folders as they are on disk.");

    companion object {
        fun of(raw: String) = entries.firstOrNull { it.raw == raw } ?: Folders
    }
}

/** Whether this server is new and waiting for its first account. */
suspend fun Server.needsFirstAccount(): Boolean =
    runCatching { JSONObject(get("Lumiere/Setup")).optBoolean("NeedsAccount") }.getOrDefault(false)

/** Makes the server's first account and signs in with it. */
suspend fun Server.createFirstAccount(user: String, password: String): Session {
    val reply = JSONObject(post("Lumiere/Setup/Account", JSONObject().put("Username", user).put("Password", password)))
    val token = reply.getString("AccessToken")
    val u = reply.getJSONObject("User")
    this.token = token
    val name = runCatching { publicInfo().optString("ServerName") }.getOrDefault("Lumiere")
    return Session(baseUrl, u.getString("Id"), u.optString("Name"), token, name)
}

suspend fun Server.libraries(): List<ServerLibrary> {
    val list = JSONObject(get("Lumiere/Libraries")).optJSONArray("Libraries") ?: JSONArray()
    return (0 until list.length()).map { i ->
        val o = list.getJSONObject(i)
        val folders = o.optJSONArray("Folders") ?: JSONArray()
        ServerLibrary(
            o.getString("Id"), o.optString("Name"), o.optString("CollectionType"),
            (0 until folders.length()).map { f -> folders.getJSONObject(f).let { LibraryFolder(it.getString("Id"), it.optString("Path")) } },
            o.optInt("ItemCount"),
        )
    }
}

suspend fun Server.createLibrary(name: String, kind: LibraryKind, paths: List<String>) {
    post("Lumiere/Libraries", JSONObject().put("Name", name).put("CollectionType", kind.raw).put("Paths", JSONArray(paths)))
}

suspend fun Server.setLibraryKind(id: String, kind: LibraryKind) {
    post("Lumiere/Libraries/$id", JSONObject().put("CollectionType", kind.raw))
}

suspend fun Server.removeLibrary(id: String) { delete("Lumiere/Libraries/$id") }

suspend fun Server.addLibraryFolder(id: String, path: String) {
    post("Lumiere/Libraries/$id/Folders", JSONObject().put("Path", path))
}

suspend fun Server.removeLibraryFolder(id: String, folderId: String) { delete("Lumiere/Libraries/$id/Folders/$folderId") }

/** The folders inside [path] on the server; with none, the usual starting places. */
suspend fun Server.browse(path: String?): Pair<String?, List<FolderEntry>> {
    val o = JSONObject(get("Lumiere/Browse", mapOf("path" to path)))
    val list = o.optJSONArray("Folders") ?: JSONArray()
    val parent = o.optString("Parent").takeIf { it.isNotBlank() && path != null }
    return parent to (0 until list.length()).map { list.getJSONObject(it).let { e -> FolderEntry(e.optString("Name"), e.optString("Path")) } }
}

/** The private libraries, kept on the server so every device follows them. */
suspend fun Server.setPrivateLibraries(ids: Set<String>) {
    post("Lumiere/Private", JSONObject().put("Libraries", JSONArray(ids.sorted())))
}

/** The movie database key, kept by the server. */
suspend fun Server.setMetadataKey(token: String) {
    post("Metadata/Key", JSONObject().put("Token", token))
    runCatching { post("Metadata/Run") }
}

suspend fun Server.changePassword(current: String, new: String) {
    post("Lumiere/Account/Password", JSONObject().put("Current", current).put("New", new))
}
