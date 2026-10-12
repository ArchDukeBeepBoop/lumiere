package app.lumiere.android

import android.content.Context
import app.lumiere.android.Probe.Status
import app.lumiere.android.api.privateLibraries
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Diagnostics' full check, run on request: each part of the app asked now
 * whether it works, and the answer kept in Probe beside what the parts
 * reported as they ran (the places loading, the walls, captions, sound).
 * Nothing here changes anything; it only looks.
 */
object SelfTest {
    /** The baked places' models a complete build carries (LumiereSpace). */
    val MODELS = listOf("cinema", "cinema_curtain", "palace", "palace_curtain", "cabin", "cabin_sofa", "winter",
        "lakeside", "terrace", "moonbase", "station", "drivein", "rooftop", "sea")
    /** The places' skies (Sky). */
    val SKIES = listOf("lumiere_lakeside", "lumiere_clouds", "lumiere_moon", "lumiere_orbit", "lumiere_starfield",
        "lumiere_drivein", "lumiere_city", "lumiere_winter", "lumiere_sea")

    suspend fun run(context: Context, state: AppState) = withContext(Dispatchers.IO) {
        listOf("crashes", "memory", "build", "assets", "permissions", "server", "private room", "on this device", "sound").forEach { Probe.clear(it) }
        step("build") { build(context) }
        step("crashes") { crashes(context) }
        step("memory") { memory() }
        step("assets") { assets(context) }
        step("permissions") { permissions(context) }
        step("server") { server(state) }
        step("private room") { privateRoom(state) }
        step("on this device") { app.lumiere.android.local.LocalVideos.list(context) }
        step("sound") { sound(context) }
    }

    private suspend fun step(area: String, check: suspend () -> Unit) {
        val done = withTimeoutOrNull(20_000) { runCatching { check() }.onFailure { Probe.fail(area, "check", "the check itself failed: ${Probe.why(it)}") } }
        if (done == null) Probe.fail(area, "check", "no answer in 20 s")
    }

    private fun build(context: Context) {
        Probe.info("build", "running", AppBuild.stamp)
        val pm = context.packageManager
        val info = runCatching { pm.getPackageInfo(context.packageName, 0) }.getOrNull()
        val clock = java.text.SimpleDateFormat("d MMM yyyy HH:mm 'UTC'", java.util.Locale.ROOT).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
        if (info != null) {
            val updated = info.lastUpdateTime
            val age = (System.currentTimeMillis() - updated) / 60_000
            Probe.info("build", "installed", "${context.packageName}, first installed ${clock.format(java.util.Date(info.firstInstallTime))}, " +
                "last updated ${clock.format(java.util.Date(updated))} ($age min ago)")
            if (AppBuild.builtAt > 0 && updated + 60_000 < AppBuild.builtAt)
                Probe.fail("build", "installed", "the install time is before this build was made: the clock is off, or this isn't the build you installed")
        }
        val others = listOf("app.lumiere.android", "app.lumiere.android.quest", "app.lumiere.android.spatial").filter { it != context.packageName }
            .filter { runCatching { pm.getPackageInfo(it, 0) }.isSuccess }
        if (others.isNotEmpty()) Probe.warn("build", "other Lumieres", "also installed: ${others.joinToString()} — make sure you open the one you just updated " +
            "(this one is ${context.packageName})")
        else Probe.ok("build", "other Lumieres", "only this Lumiere is installed")
    }

    private fun crashes(context: Context) {
        val last = CrashLog.last(context)
        if (last == null) Probe.ok("crashes", "last crash", "none recorded")
        else Probe.warn("crashes", "last crash", CrashLog.essentials(last, 14).replace("\n", " ⏎ "))
        exits(context)
        Breadcrumbs.previous(context).takeIf { it.isNotBlank() }?.let {
            Probe.info("crashes", "last start's steps", it.lines().takeLast(25).joinToString(" ⏎ "))
        }
        Probe.info("crashes", "this start's steps", Breadcrumbs.current(context).lines().takeLast(12).joinToString(" ⏎ "))
        val unsettled = context.getSharedPreferences("start", Context.MODE_PRIVATE).getInt("unsettled", 0)
        if (unsettled > 0) Probe.info("crashes", "early ends", "$unsettled recent start(s) ended within ${StartGuard.SETTLE_MS / 1000} s")
    }

    /** How the last runs ended, as Android recorded it: a native crash's backtrace, an ANR's stacks, a kill for memory. */
    private fun exits(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < 30) return
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val exits = runCatching { am.getHistoricalProcessExitReasons(context.packageName, 0, 6) }.getOrNull().orEmpty()
        val clock = java.text.SimpleDateFormat("d MMM HH:mm:ss", java.util.Locale.ROOT)
        exits.forEachIndexed { i, e ->
            val reason = when (e.reason) {
                android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "NATIVE CRASH"
                android.app.ApplicationExitInfo.REASON_CRASH -> "CRASH (Java/Kotlin)"
                android.app.ApplicationExitInfo.REASON_ANR -> "NOT RESPONDING (ANR)"
                android.app.ApplicationExitInfo.REASON_LOW_MEMORY -> "killed: low memory"
                android.app.ApplicationExitInfo.REASON_SIGNALED -> "killed by signal ${e.status}"
                android.app.ApplicationExitInfo.REASON_EXIT_SELF -> "exited itself"
                android.app.ApplicationExitInfo.REASON_USER_REQUESTED -> "closed by you / the system UI"
                android.app.ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "app updated"
                android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "killed: excessive resource use"
                android.app.ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "a dependency died"
                android.app.ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "failed to start"
                android.app.ApplicationExitInfo.REASON_OTHER -> "other"
                else -> "reason ${e.reason}"
            }
            val bad = e.reason in setOf(android.app.ApplicationExitInfo.REASON_CRASH_NATIVE, android.app.ApplicationExitInfo.REASON_CRASH,
                android.app.ApplicationExitInfo.REASON_ANR, android.app.ApplicationExitInfo.REASON_LOW_MEMORY,
                android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE, android.app.ApplicationExitInfo.REASON_INITIALIZATION_FAILURE)
            val trace = if (e.reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE || e.reason == android.app.ApplicationExitInfo.REASON_ANR)
                runCatching { e.traceInputStream?.use { it.readBytes() } }.getOrNull()?.let { traceLines(it, e.reason == android.app.ApplicationExitInfo.REASON_ANR) } else null
            Probe.report("crashes", "exit ${i + 1}: ${clock.format(java.util.Date(e.timestamp))}", if (bad) Status.FAIL else Status.INFO,
                "$reason${e.description?.let { " — $it" } ?: ""}; memory then ${e.pss / 1024} MB (rss ${e.rss / 1024} MB)" +
                    (trace?.let { " ⏎ $it" } ?: ""))
        }
        if (exits.isEmpty()) Probe.info("crashes", "exits", "Android has no record of how earlier runs ended")
    }

    /** The readable part of a trace: a native tombstone's frames (it's binary) or an ANR's main thread. */
    private fun traceLines(bytes: ByteArray, anr: Boolean): String {
        if (anr) {
            val text = String(bytes)
            val main = text.substringAfter("\"main\"", text).lines().take(30)
            return main.joinToString(" ⏎ ")
        }
        // Printable runs from the tombstone's protobuf: the signal, abort message, and frames (library + function).
        val runs = mutableListOf<String>()
        val sb = StringBuilder()
        for (b in bytes) {
            val c = b.toInt() and 0xFF
            if (c in 32..126) sb.append(c.toChar()) else { if (sb.length >= 5) runs += sb.toString(); sb.setLength(0) }
        }
        if (sb.length >= 5) runs += sb.toString()
        val interesting = runs.filter { r ->
            r.startsWith("SIG") || "Abort" in r || "abort" in r || ".so" in r || "::" in r || "app.lumiere" in r || "com.meta" in r ||
                "Exception" in r || "Error" in r || "fault" in r
        }.distinct()
        return interesting.take(40).joinToString(" ⏎ ")
    }

    private fun memory() {
        val rt = Runtime.getRuntime()
        val used = (rt.totalMemory() - rt.freeMemory()) / 1_048_576
        val max = rt.maxMemory() / 1_048_576
        Probe.report("memory", "heap", if (used > max * 0.85) Status.WARN else Status.OK,
            "$used of $max MB in use; native ${android.os.Debug.getNativeHeapAllocatedSize() / 1_048_576} MB; device ${Device.totalMb} MB")
    }

    private fun assets(context: Context) {
        val am = context.assets
        val present = runCatching { am.list("environments")?.toSet() }.getOrNull().orEmpty()
        for (m in MODELS) {
            if ("$m.glb" !in present) { Probe.fail("assets", "$m.glb", "missing from this build: that place shows its plain blocks"); continue }
            val size = runCatching { am.openFd("environments/$m.glb").use { it.length } }.getOrElse { runCatching { am.open("environments/$m.glb").use { it.available().toLong() } }.getOrDefault(-1) }
            val atlases = runCatching { am.list("environments/$m")?.toList() }.getOrNull().orEmpty().filter { it.endsWith(".jpg") }
            val broken = atlases.filter { a ->
                val o = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                runCatching { am.open("environments/$m/$a").use { android.graphics.BitmapFactory.decodeStream(it, null, o) } }
                o.outWidth <= 0
            }
            Probe.report("assets", "$m.glb", when { atlases.isEmpty() -> Status.FAIL; broken.isNotEmpty() -> Status.FAIL; else -> Status.OK },
                "${size / 1024} KB, ${atlases.size} baked atlas(es)" +
                    (if (atlases.isEmpty()) " — none: the place would show white" else "") +
                    (if (broken.isNotEmpty()) "; unreadable: ${broken.joinToString()}" else ""))
        }
        val skies = SKIES.map { it to context.resources.getIdentifier(it, "drawable", context.packageName) }
        val missing = skies.filter { it.second == 0 }.map { it.first }
        Probe.report("assets", "skies", if (missing.isEmpty()) Status.OK else Status.FAIL,
            "${skies.size - missing.size} of ${skies.size} skies in this build" + (if (missing.isNotEmpty()) "; missing ${missing.joinToString()}" else ""))
    }

    private fun permissions(context: Context) {
        val info = runCatching { context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS) }.getOrNull()
        val asked = info?.requestedPermissions.orEmpty().toList()
        val matters = mapOf(
            "com.oculus.permission.USE_SCENE" to "your room's walls, for Wall",
            "android.permission.READ_MEDIA_VIDEO" to "videos on this headset",
            "com.oculus.permission.HAND_TRACKING" to "hands",
            "android.permission.POST_NOTIFICATIONS" to "the music's controls",
        )
        for ((p, why) in matters) {
            val name = p.substringAfterLast('.')
            when {
                p !in asked -> Probe.fail("permissions", name, "not declared in this build's manifest ($why)")
                context.checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED -> Probe.ok("permissions", name, "granted ($why)")
                else -> Probe.warn("permissions", name, "not granted yet ($why); asked the first time it's needed, or allow it in Settings > Apps > Lumiere")
            }
        }
    }

    private suspend fun server(state: AppState) {
        val s = state.server ?: return Probe.fail("server", "signed in", "not signed in to a server")
        Probe.ok("server", "signed in", "as ${state.session?.userName ?: "?"} on ${state.session?.serverUrl ?: "?"}")
        val t = System.currentTimeMillis()
        runCatching { s.publicInfo() }
            .onSuccess { Probe.ok("server", "reachable", "${it.optString("ServerName")} ${it.optString("Version")}, answered in ${System.currentTimeMillis() - t} ms") }
            .onFailure { Probe.fail("server", "reachable", Probe.why(it)) }
    }

    private suspend fun privateRoom(state: AppState) {
        val s = state.server ?: return Probe.fail("private room", "libraries", "not signed in")
        val user = state.session?.userId ?: return
        val views = runCatching { s.views(user) }.onFailure { Probe.fail("private room", "libraries", "couldn't list libraries: ${Probe.why(it)}") }.getOrNull() ?: return
        Probe.info("private room", "libraries", "${views.size} on the server: " + views.joinToString { "${it.name} (${it.id.take(8)})" })
        val follows = state.settings.privateFollowsMac
        val fromMac = if (follows) runCatching { s.privateLibraries() }
            .onFailure { Probe.fail("private room", "from the Mac", "the Mac's private list couldn't be read: ${Probe.why(it)}") }.getOrNull() else null
        val raw = if (follows) fromMac ?: state.macPrivate else state.settings.privateLibraries
        val matched = RoomLibraries.match(raw, views.map { it.id })
        val unmatched = raw.filter { r -> views.none { RoomLibraries.same(it.id, r) } }
        Probe.report("private room", "which are private", when { raw.isEmpty() -> Status.FAIL; unmatched.isNotEmpty() -> Status.WARN; else -> Status.OK },
            "set ${if (follows) "on the Mac" else "here, in Settings"}: ${raw.size} id(s)" +
                (if (raw.isEmpty()) " — none, so the private room is empty" else "") +
                "; matched to ${matched.size} of this account's libraries: " + views.filter { it.id in matched }.joinToString { it.name } +
                (if (unmatched.isNotEmpty()) "; ids that match none of this account's libraries: ${unmatched.joinToString { it.take(8) }}" else "") +
                "; the app holds ${state.privateLibraries.size} (known ${state.privacyKnown})")
        for (v in views.filter { it.id in matched }) {
            runCatching { s.library(user, v.id, 0, 5) }
                .onSuccess { Probe.report("private room", v.name, if (it.isEmpty()) Status.WARN else Status.OK,
                    if (it.isEmpty()) "no titles came back for this library" else "titles come back (e.g. ${it.size} of the first 5); tagged to this library: ${it.count { i -> i.libraryId == v.id }}") }
                .onFailure { Probe.fail("private room", v.name, "listing failed: ${Probe.why(it)}") }
        }
        val open = state.roomOpen
        val shown = state.visibleViews(views)
        Probe.info("private room", "now", "room ${if (open) "open" else "shut"}: ${shown.size} libraries shown (${shown.joinToString { it.name }})")
    }

    private fun sound(context: Context) {
        val outs = app.lumiere.android.player.AudioOutputs.list(context)
        Probe.report("sound", "outputs", if (outs.isEmpty()) Status.WARN else Status.OK,
            "${outs.size} now: " + outs.joinToString { "${it.name} (${it.kind})" } +
                "; chosen ${app.lumiere.android.player.AudioOutputs.chosen ?: "the system's"}" +
                (if (outs.none { it.kind == app.lumiere.android.player.AudioOutputs.Kind.BLUETOOTH }) "; no Bluetooth output connected" else ""))
    }

    /** The whole report, as text: the build, every check grouped by area with problems first, then the notes and system log. */
    fun text(): String {
        val results = Probe.all()
        val order = listOf(Status.FAIL, Status.WARN, Status.OK, Status.INFO)
        val head = buildString {
            appendLine("LUMIERE DIAGNOSTICS — ${AppBuild.stamp}")
            appendLine("taken ${java.util.Date()}")
            appendLine("${results.count { it.status == Status.FAIL }} failing, ${results.count { it.status == Status.WARN }} warnings, " +
                "${results.count { it.status == Status.OK }} working")
            appendLine()
            results.groupBy { it.area }.forEach { (area, rs) ->
                appendLine("== ${area.uppercase()} ==")
                rs.sortedBy { order.indexOf(it.status) }.forEach { r ->
                    appendLine("[${r.status}] ${r.name}: ${r.detail}")
                }
                appendLine()
            }
        }
        return head + Diagnostics.report()
    }

    /** The report saved to the headset's Download/Lumiere folder (open it in Files, or take it off with SideQuest); its path, or why not. */
    fun save(context: Context): String = runCatching {
        val name = "lumiere-diagnostics-" + java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.ROOT).format(java.util.Date()) + ".txt"
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
            put(android.provider.MediaStore.Downloads.MIME_TYPE, "text/plain")
            put(android.provider.MediaStore.Downloads.RELATIVE_PATH, "Download/Lumiere")
        }
        val uri = context.contentResolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("the Downloads folder refused the file")
        context.contentResolver.openOutputStream(uri)!!.use { it.write(text().toByteArray()) }
        "Saved to Download/Lumiere/$name"
    }.getOrElse { "Couldn't save: ${Probe.why(it)}" }
}
