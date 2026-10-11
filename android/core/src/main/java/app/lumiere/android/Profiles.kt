package app.lumiere.android

import app.lumiere.android.api.Session
import org.json.JSONArray
import org.json.JSONObject

/**
 * One person signed in on this device, as Netflix and the Apple TV app keep
 * them for "Who's watching?": their session on the server, and the tag of the
 * picture the server keeps for them, when it keeps one.
 */
data class Profile(val session: Session, val imageTag: String? = null) {
    /** Who this is, whichever server: the same key the library copy's owner is kept under. */
    val key: String get() = Profiles.key(session)
    val name: String get() = session.userName
}

/**
 * The profiles saved on this device: one string of JSON in the preferences
 * (Prefs.profilesJson), written and read here so it can be tested. The single
 * session kept before there were profiles comes in as the first of them.
 */
object Profiles {
    fun key(serverUrl: String, userId: String) = "$serverUrl|$userId"
    fun key(session: Session) = key(session.serverUrl, session.userId)

    fun encode(profiles: List<Profile>): String = JSONArray().apply {
        profiles.forEach { p ->
            put(JSONObject().put("server", p.session.serverUrl).put("userId", p.session.userId)
                .put("userName", p.session.userName).put("token", p.session.token)
                .put("serverName", p.session.serverName).apply { p.imageTag?.let { put("imageTag", it) } })
        }
    }.toString()

    /**
     * What [encode] wrote. A profile missing its server, user or token is left
     * out, and anything unreadable reads as none: a bad save must never stop the
     * app at start, it only means signing in again.
     */
    fun decode(json: String?): List<Profile> {
        val array = runCatching { JSONArray(json ?: return emptyList()) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val o = array.optJSONObject(i) ?: return@mapNotNull null
            val url = o.text("server") ?: return@mapNotNull null
            val userId = o.text("userId") ?: return@mapNotNull null
            val token = o.text("token") ?: return@mapNotNull null
            Profile(Session(url, userId, o.text("userName") ?: "", token, o.text("serverName") ?: "Lumiere"), o.text("imageTag"))
        }.distinctBy { it.key }
    }

    // org.json reads a JSON null as the word "null" on Android, and as nothing in the tests' copy.
    private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }

    /**
     * The saved profiles with [current], the session kept the way it was before
     * profiles: first when it isn't among them yet (the one person signed in on
     * an older version), else in its own place with its newer token.
     */
    fun migrate(saved: List<Profile>, current: Session?): List<Profile> = when {
        current == null -> saved
        saved.none { it.key == key(current) } -> listOf(Profile(current)) + saved
        else -> saved.map { if (it.key == key(current)) it.copy(session = current) else it }
    }

    /** [profile] kept: in its own place when it's here already (a new token, a new picture), else last. */
    fun upsert(profiles: List<Profile>, profile: Profile): List<Profile> =
        if (profiles.any { it.key == profile.key }) profiles.map { if (it.key == profile.key) profile else it }
        else profiles + profile

    /** Where the app goes: signing in, "Who's watching?", or on with whoever is watching. */
    enum class Start { SignIn, Choose, Home }

    /**
     * Where the app opens. Nobody saved: sign in. Someone saved but nobody
     * current (they signed out): choose. Two or more, and asked to: choose.
     */
    fun start(profiles: Int, signedIn: Boolean, askAtStart: Boolean): Start = when {
        profiles == 0 && !signedIn -> Start.SignIn
        !signedIn -> Start.Choose
        askAtStart && profiles >= 2 -> Start.Choose
        else -> Start.Home
    }

    /**
     * [key] taken off this device: the profiles left, and where the app goes. Someone
     * else removed: on as before ([Start.Home]). The one watching removed: the rest
     * choose, or, with nobody left, sign in.
     */
    fun remove(profiles: List<Profile>, key: String, current: String?): Pair<List<Profile>, Start> {
        val rest = profiles.filter { it.key != key }
        return rest to when {
            key != current -> Start.Home
            rest.isEmpty() -> Start.SignIn
            else -> Start.Choose
        }
    }

    /**
     * What a person did on this device under [keys] in the preferences, kept apart
     * from the next person's: the writes (null removes) that put [from]'s away under
     * their own key and bring [to]'s back. [from] null leaves nothing behind: they
     * signed out or were removed.
     */
    fun swap(keys: List<String>, read: (String) -> String?, from: String?, to: String): Map<String, String?> {
        if (from == to) return emptyMap()
        val out = linkedMapOf<String, String?>()
        keys.forEach { k ->
            if (from != null) out["$k@$from"] = read(k)
            out[k] = read("$k@$to")
            out["$k@$to"] = null
        }
        return out
    }

    /** The first letter of [name], for a profile with no picture: whole, if it's an emoji or an accent. */
    fun initial(name: String): String {
        val t = name.trim()
        if (t.isEmpty()) return "?"
        return String(Character.toChars(t.codePointAt(0))).uppercase()
    }

    /** Which of [count] colours a profile with no picture wears: always the same one for the same person. */
    fun tint(key: String, count: Int): Int = Math.floorMod(key.hashCode(), count)
}
