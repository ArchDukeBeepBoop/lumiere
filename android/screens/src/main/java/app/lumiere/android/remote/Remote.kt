package app.lumiere.android.remote

import org.json.JSONArray
import org.json.JSONObject

/**
 * The phone-as-remote protocol, shared by both ends. The TV advertises
 * itself on the home Wi-Fi (NSD, [SERVICE_TYPE]) and listens on a TCP port;
 * each side sends one JSON object per line. The Mac's server is not
 * involved: it has no remote-control routes.
 *
 * Phone → TV
 *   {"t":"pair","code":"1234","device":"<phone id>","name":"Galaxy S24+"}  first time, the code the TV shows
 *   {"t":"hello","device":"<phone id>","token":"<from paired>"}            every later connection
 *   {"t":"key","key":"up|down|left|right|ok|back|home|menu|playpause|volup|voldown|mute"}
 *   {"t":"text","text":"..."}                 replaces what is typed in the focused search field
 *   {"t":"seek","seconds":123.0}              to a place in what is playing
 *   {"t":"skip","by":10}                      seconds, negative for back
 *   {"t":"audio","index":2}                   an audio stream index, as in the item's streams
 *   {"t":"subtitle","index":3}                a subtitle stream index, -1 for off
 *   {"t":"play","item":"<id>","start":0.0}    open the player on the TV; start omitted to resume
 *
 * TV → phone
 *   {"t":"paired","token":"..."}              keep it; the TV keeps it per phone id
 *   {"t":"refused","why":"wrong code"}        then the connection closes
 *   {"t":"welcome","name":"Projector"}        after a good hello or pair
 *   {"t":"state", ...}                        see [TvState]; on welcome, on every change, and each second while playing
 */
object Remote {
    const val SERVICE_TYPE = "_lumiere-remote._tcp."

    val KEYS = setOf("up", "down", "left", "right", "ok", "back", "home", "menu", "playpause", "volup", "voldown", "mute")

    fun pair(code: String, device: String, name: String) =
        JSONObject().put("t", "pair").put("code", code).put("device", device).put("name", name)
    fun hello(device: String, token: String) = JSONObject().put("t", "hello").put("device", device).put("token", token)
    fun key(key: String) = JSONObject().put("t", "key").put("key", key)
    fun text(text: String) = JSONObject().put("t", "text").put("text", text)
    fun seek(seconds: Double) = JSONObject().put("t", "seek").put("seconds", seconds)
    fun skip(by: Int) = JSONObject().put("t", "skip").put("by", by)
    fun audio(index: Int) = JSONObject().put("t", "audio").put("index", index)
    fun subtitle(index: Int) = JSONObject().put("t", "subtitle").put("index", index)
    fun play(item: String, start: Double?) = JSONObject().put("t", "play").put("item", item)
        .apply { if (start != null) put("start", start) }
}

/** One audio or subtitle choice on the TV. */
data class TvTrack(val index: Int, val label: String, val selected: Boolean) {
    fun json(): JSONObject = JSONObject().put("index", index).put("label", label).put("selected", selected)
    companion object {
        fun from(o: JSONObject) = TvTrack(o.getInt("index"), o.optString("label"), o.optBoolean("selected"))
    }
}

/**
 * What the TV is doing. [itemId] null when nothing plays. [isPrivate] when it
 * comes from the private room: the phone then shows only that something is
 * playing, never what — the phone may be in other hands.
 */
data class TvState(
    val itemId: String? = null,
    val title: String = "",
    val subtitle: String = "",
    val isPrivate: Boolean = false,
    val position: Double = 0.0,
    val duration: Double = 0.0,
    val playing: Boolean = false,
    val audio: List<TvTrack> = emptyList(),
    val subtitles: List<TvTrack> = emptyList(),
    /** A text field has focus on the TV: the phone offers its keyboard. */
    val typing: Boolean = false,
) {
    fun json(): JSONObject = JSONObject().put("t", "state")
        .put("item", itemId ?: JSONObject.NULL).put("title", title).put("subtitle", subtitle)
        .put("private", isPrivate).put("position", position).put("duration", duration).put("playing", playing)
        .put("audio", JSONArray(audio.map { it.json() })).put("subtitles", JSONArray(subtitles.map { it.json() }))
        .put("typing", typing)

    companion object {
        fun from(o: JSONObject) = TvState(
            itemId = o.optString("item").takeIf { !o.isNull("item") && it.isNotEmpty() },
            title = o.optString("title"), subtitle = o.optString("subtitle"),
            isPrivate = o.optBoolean("private"),
            position = o.optDouble("position", 0.0), duration = o.optDouble("duration", 0.0),
            playing = o.optBoolean("playing"),
            audio = o.optJSONArray("audio").tracks(), subtitles = o.optJSONArray("subtitles").tracks(),
            typing = o.optBoolean("typing"),
        )

        private fun JSONArray?.tracks(): List<TvTrack> =
            if (this == null) emptyList() else (0 until length()).map { TvTrack.from(getJSONObject(it)) }
    }
}
