package app.lumiere.android

/**
 * How each part of the app is doing right now, for Diagnostics: every part
 * that can quietly not work (a place's model, its baked pictures, the walls
 * from Space Setup, the private room's libraries, captions, the sound's
 * output, videos on the device) says here what it last did and whether it
 * worked, with the real reason when it didn't. The latest word on each thing
 * stands; each is also written to the system log under "LumiereProbe".
 */
object Probe {
    enum class Status { OK, WARN, FAIL, INFO }

    data class Result(val area: String, val name: String, val status: Status, val detail: String, val at: Long)

    private val results = LinkedHashMap<String, Result>()

    @Synchronized
    fun report(area: String, name: String, status: Status, detail: String) {
        val was = results["$area/$name"]
        results["$area/$name"] = Result(area, name, status, detail, System.currentTimeMillis())
        if (was != null && was.status == status && was.detail == detail) return
        runCatching {
            val line = "[$area] $name: $status $detail"
            if (status == Status.FAIL) android.util.Log.e("LumiereProbe", line) else android.util.Log.i("LumiereProbe", line)
        }
    }

    fun ok(area: String, name: String, detail: String) = report(area, name, Status.OK, detail)
    fun warn(area: String, name: String, detail: String) = report(area, name, Status.WARN, detail)
    fun fail(area: String, name: String, detail: String) = report(area, name, Status.FAIL, detail)
    fun info(area: String, name: String, detail: String) = report(area, name, Status.INFO, detail)

    /** An error as one line: its kind and message, and its cause's. */
    fun why(e: Throwable?): String = when (e) {
        null -> "no error given"
        else -> buildString {
            append(e.javaClass.simpleName).append(": ").append(e.message ?: "(no message)")
            e.cause?.takeIf { it !== e }?.let { append(" ← ").append(it.javaClass.simpleName).append(": ").append(it.message ?: "") }
        }
    }

    @Synchronized
    fun all(): List<Result> = results.values.toList()

    @Synchronized
    fun clear(area: String) { results.keys.removeAll { it.startsWith("$area/") } }
}
