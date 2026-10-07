package app.lumiere.android.remote

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The TV's end of the phone remote (see [Remote] for the protocol). It listens
 * on the home Wi-Fi and advertises itself; a phone it has never met is shown a
 * four-digit code on the TV and must send it back, and gets a token to use from
 * then on. Nothing is obeyed from a connection that has not paired.
 *
 * What it controls is handed in by the screens: [actions] by the activity, the
 * player's part by the player while it is open, the search field by Search.
 */
object RemoteHost {
    /** What the TV does for a phone; the activity fills it in. */
    class Actions(
        val key: (String) -> Unit,
        val play: (itemId: String, start: Double?) -> Unit,
    )

    /** The player's side while a title is open; null otherwise. */
    class PlayerHooks(
        val seek: (Double) -> Unit,
        val skip: (Int) -> Unit,
        val audio: (Int) -> Unit,
        val subtitle: (Int) -> Unit,
        val state: () -> TvState,
    )

    var actions: Actions? = null
    var player: PlayerHooks? = null
        set(v) { field = v; pushState() }
    /** Search's field, while Search is open: what the phone types replaces it. */
    var typing: ((String) -> Unit)? = null
        set(v) { field = v; pushState() }

    /** The code on screen for a phone to send, or null. */
    var code by mutableStateOf<String?>(null)
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var server: ServerSocket? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var ticker: Job? = null
    private val phones = CopyOnWriteArrayList<PrintWriter>()
    private val random = SecureRandom()

    private fun prefs(context: Context) = context.getSharedPreferences("lumiere.remote.host", Context.MODE_PRIVATE)

    /** Starts listening and advertising; once per process. */
    fun start(context: Context, name: String) {
        if (server != null) return
        val app = context.applicationContext
        scope.launch {
            val s = runCatching { ServerSocket(0) }.getOrNull() ?: return@launch
            server = s
            withContext(Dispatchers.Main) { advertise(app, name, s.localPort) }
            while (!s.isClosed) {
                val socket = runCatching { s.accept() }.getOrNull() ?: break
                launch { serve(app, name, socket) }
            }
        }
        ticker = scope.launch { while (true) { delay(1000); if (player != null && phones.isNotEmpty()) pushState() } }
    }

    fun stop(context: Context) {
        registration?.let { runCatching { (context.getSystemService(Context.NSD_SERVICE) as NsdManager).unregisterService(it) } }
        registration = null
        runCatching { server?.close() }
        server = null
        ticker?.cancel()
        phones.clear()
        code = null
    }

    /** Every phone forgotten: each must pair again. */
    fun forgetAll(context: Context) = prefs(context).edit().clear().apply()

    private fun advertise(context: Context, name: String, port: Int) {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val info = NsdServiceInfo().apply { serviceName = name; serviceType = Remote.SERVICE_TYPE; this.port = port }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {}
            override fun onRegistrationFailed(info: NsdServiceInfo, error: Int) {}
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, error: Int) {}
        }
        registration = listener
        runCatching { nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener) }
    }

    private suspend fun serve(context: Context, name: String, socket: Socket) = runCatching {
        socket.use { s ->
            s.tcpNoDelay = true
            val out = PrintWriter(s.getOutputStream(), true)
            val lines = BufferedReader(InputStreamReader(s.getInputStream()))
            // A phone that has not paired opens the connection and waits: show the code.
            // A blocking read ignores coroutine timeouts, so the socket's own timeout decides.
            s.soTimeout = 1500
            val first = try { lines.readLine() } catch (_: java.net.SocketTimeoutException) { null }
            if (first == null) {
                showCode()
                s.soTimeout = 120_000
                runCatching { lines.readLine() }
                return@use
            }
            s.soTimeout = 0
            if (!admit(context, name, JSONObject(first), out)) return@use
            phones += out
            try {
                pushState()
                while (true) {
                    val line = lines.readLine() ?: break
                    val o = runCatching { JSONObject(line) }.getOrNull() ?: continue
                    withContext(Dispatchers.Main) { obey(o) }
                }
            } finally { phones -= out }
        }
    }

    /** Shows a fresh code now, from Settings, for a phone about to pair. */
    fun pairNow() = showCode()

    private fun showCode() {
        code = (0 until 4).joinToString("") { random.nextInt(10).toString() }
        scope.launch { val shown = code; delay(5 * 60_000L); if (code == shown) code = null }
    }

    /** A pair with the code on screen, or a hello with a token given before. */
    private fun admit(context: Context, name: String, o: JSONObject, out: PrintWriter): Boolean {
        val device = o.optString("device")
        when (o.optString("t")) {
            "pair" -> {
                val shown = code
                if (shown == null || o.optString("code") != shown || device.isEmpty()) {
                    out.println(JSONObject().put("t", "refused").put("why", "That code doesn't match the one on the TV.")); return false
                }
                val token = ByteArray(24).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }
                prefs(context).edit().putString(device, token).putString("$device.name", o.optString("name")).apply()
                code = null
                out.println(JSONObject().put("t", "paired").put("token", token))
            }
            "hello" -> {
                val known = prefs(context).getString(device, null)
                if (known == null || known != o.optString("token")) {
                    out.println(JSONObject().put("t", "refused").put("why", "This TV doesn't know this phone any more. Pair again.")); return false
                }
            }
            else -> { out.println(JSONObject().put("t", "refused").put("why", "Pair first.")); return false }
        }
        out.println(JSONObject().put("t", "welcome").put("name", name))
        // A word on the TV that a phone has taken hold — who it is, never silent.
        val phone = prefs(context).getString("$device.name", null) ?: "A phone"
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            android.widget.Toast.makeText(context, "$phone is connected as a remote", android.widget.Toast.LENGTH_SHORT).show()
        }
        return true
    }

    private fun obey(o: JSONObject) {
        val p = player
        when (o.optString("t")) {
            "key" -> o.optString("key").takeIf { it in Remote.KEYS }?.let { actions?.key?.invoke(it) }
            "text" -> typing?.invoke(o.optString("text").take(80))
            "seek" -> p?.seek?.invoke(o.optDouble("seconds", 0.0))
            "skip" -> p?.skip?.invoke(o.optInt("by"))
            "audio" -> p?.audio?.invoke(o.optInt("index"))
            "subtitle" -> p?.subtitle?.invoke(o.optInt("index", -1))
            "play" -> o.optString("item").takeIf { it.isNotEmpty() }?.let { id ->
                actions?.play?.invoke(id, if (o.has("start")) o.optDouble("start") else null)
            }
        }
        pushState()
    }

    /** What the TV is doing, to every phone; on change and each second while a title plays. */
    fun pushState() {
        if (phones.isEmpty()) return
        val st = (runCatching { player?.state?.invoke() }.getOrNull() ?: TvState()).copy(typing = typing != null)
        val line = st.json().toString()
        scope.launch { phones.forEach { runCatching { it.println(line) } } }
    }
}
