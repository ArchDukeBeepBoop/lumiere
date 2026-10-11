package app.lumiere.android.api

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONArray
import org.json.JSONObject

/** Someone the server lists before sign-in (Users/Public): "Who's watching?" offers them to add. */
data class PublicUser(val id: String, val name: String, val imageTag: String?, val hasPassword: Boolean)

/**
 * Users/Public's answer. A user saying nothing of a password is asked for one:
 * an empty field is quicker to pass than a refusal is to understand.
 */
fun parsePublicUsers(body: String): List<PublicUser> {
    val array = runCatching { JSONArray(body.trim()) }.getOrNull() ?: return emptyList()
    return (0 until array.length()).mapNotNull { i ->
        val o = array.optJSONObject(i) ?: return@mapNotNull null
        val id = o.text("Id") ?: return@mapNotNull null
        PublicUser(id, o.text("Name") ?: "", o.text("PrimaryImageTag"), o.optBoolean("HasPassword", true))
    }
}

private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }

/** The people this server shows before sign-in; none when it keeps them hidden, as Lumiere's own does. */
suspend fun Server.publicUsers(): List<PublicUser> = parsePublicUsers(get("Users/Public"))

/** The signed-in person's picture tag (Users/Me), or null when they have none or the server keeps none. */
suspend fun Server.myImageTag(): String? = JSONObject(get("Users/Me")).let { if (it.isNull("PrimaryImageTag")) null else it.optString("PrimaryImageTag").ifEmpty { null } }

/**
 * A person's picture on [serverUrl], at [size] pixels across. Users' pictures
 * are for anyone on a Jellyfin server; the signed-in image loader adds its
 * header all the same. Null for an address that isn't one.
 */
fun userImageUrl(serverUrl: String, userId: String, tag: String, size: Int): String? {
    val base = serverUrl.trimEnd('/').toHttpUrlOrNull() ?: return null
    return base.newBuilder().addPathSegment("Users").addPathSegment(userId).addPathSegment("Images").addPathSegment("Primary")
        .addQueryParameter("tag", tag).addQueryParameter("maxWidth", "$size").addQueryParameter("quality", "90")
        .build().toString()
}
