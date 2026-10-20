package app.lumiere.android.remote

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket

/** A TV found on the Wi-Fi. */
data class FoundTv(val name: String, val host: String, val port: Int)

/**
 * The phone's end of the remote: finds Lumiere TVs on the Wi-Fi, pairs once
 * with the code the TV shows, then keeps one connection open while the
 * remote is in use. See [Remote] for the messages.
 */
object RemoteClient {
    enum class Status { Idle, Connecting, NeedsCode, Connected, Failed }

    val found = mutableStateListOf<FoundTv>()
    var status by mutableStateOf(Status.Idle)
        private set
    var tv by mutableStateOf<FoundTv?>(null)
        private set
    var state by mutableStateOf(TvState())
        private set
    var problem by mutableStateOf<String?>(null)
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var socket: Socket? = null
    private var out: PrintWriter? = null
    private var reader: Job? = null
    private var discovery: NsdManager.DiscoveryListener? = null

    private fun prefs(context: Context) = context.getSharedPreferences("lumiere.remote", Context.MODE_PRIVATE)

    /** The TV this phone last used, to connect to by itself. */
    fun lastTv(context: Context): String? = prefs(context).getString("last", null)

    fun discover(context: Context) {
        if (discovery != null) return
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(r: NsdServiceInfo) {
                        // TVs alone: anything else answering (an older copy on a headset) is passed over.
                        if (r.attributes["kind"]?.let { String(it) } != "tv") return
                        val host = r.host?.hostAddress ?: return
                        val tv = FoundTv(r.serviceName, host, r.port)
                        scope.launch(Dispatchers.Main) {
                            found.removeAll { it.name == tv.name }
                            found += tv
                            if (status == Status.Idle && tv.name == lastTv(context)) connect(context, tv)
                        }
                    }
                    override fun onResolveFailed(info: NsdServiceInfo, error: Int) {}
                })
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                scope.launch(Dispatchers.Main) { found.removeAll { it.name == info.serviceName } }
            }
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) { discovery = null }
            override fun onStopDiscoveryFailed(type: String, error: Int) {}
        }
        discovery = listener
        runCatching { nsd.discoverServices(Remote.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
            .onFailure { discovery = null }
    }

    fun stopDiscovery(context: Context) {
        val l = discovery ?: return
        discovery = null
        runCatching { (context.getSystemService(Context.NSD_SERVICE) as NsdManager).stopServiceDiscovery(l) }
    }

    /** Opens the connection; asks for the TV's code when this phone has not paired with it. */
    fun connect(context: Context, to: FoundTv) {
        disconnect()
        tv = to; problem = null
        val device = deviceId(context)
        val token = prefs(context).getString("token:${to.name}", null)
        status = Status.Connecting
        open(context, to) { if (token != null) Remote.hello(device, token) else null }
    }

    /** Sends the code the TV shows. */
    fun pair(context: Context, code: String) {
        val to = tv ?: return
        status = Status.Connecting
        open(context, to) { Remote.pair(code, deviceId(context), android.os.Build.MODEL) }
    }

    private fun open(context: Context, to: FoundTv, first: () -> JSONObject?) {
        reader?.cancel()
        reader = scope.launch {
            runCatching {
                socket?.close()
                val s = Socket().apply { connect(InetSocketAddress(to.host, to.port), 4000); tcpNoDelay = true }
                socket = s
                out = PrintWriter(s.getOutputStream(), true)
                val hello = first()
                if (hello == null) { withContext(Dispatchers.Main) { status = Status.NeedsCode }; return@runCatching }
                out?.println(hello.toString())
                val lines = BufferedReader(InputStreamReader(s.getInputStream()))
                while (true) {
                    val line = lines.readLine() ?: break
                    val o = runCatching { JSONObject(line) }.getOrNull() ?: continue
                    withContext(Dispatchers.Main) { receive(context, to, o) }
                }
                withContext(Dispatchers.Main) {
                    if (status == Status.Connected) { status = Status.Failed; problem = "${to.name} closed the connection." }
                }
            }.onFailure {
                withContext(Dispatchers.Main) {
                    if (status != Status.NeedsCode) { status = Status.Failed; problem = "Couldn't reach ${to.name}." }
                }
            }
        }
    }

    private fun receive(context: Context, to: FoundTv, o: JSONObject) {
        when (o.optString("t")) {
            "paired" -> prefs(context).edit().putString("token:${to.name}", o.getString("token")).apply()
            "welcome" -> {
                status = Status.Connected
                prefs(context).edit().putString("last", to.name).apply()
                waiting?.let { send(it); waiting = null }
            }
            "refused" -> {
                // A token the TV no longer knows (it was reset): pair again.
                prefs(context).edit().remove("token:${to.name}").apply()
                problem = o.optString("why").ifEmpty { null }
                status = Status.NeedsCode
            }
            "state" -> state = TvState.from(o)
        }
    }

    /** "Play on TV" asked before the connection was up: sent once it is. */
    private var waiting: JSONObject? = null

    /** Starts [itemId] on the TV, now or as soon as the TV answers. */
    fun playOnTv(itemId: String, start: Double?) {
        val message = Remote.play(itemId, start)
        if (status == Status.Connected) send(message) else waiting = message
    }

    fun send(message: JSONObject) {
        if (status != Status.Connected) return
        scope.launch { runCatching { out?.println(message.toString()) } }
    }

    fun disconnect() {
        reader?.cancel(); reader = null
        val s = socket; socket = null; out = null
        scope.launch { runCatching { s?.close() } }
        status = Status.Idle; state = TvState()
    }

    /** Forgets this TV's pairing, as Settings offers. */
    fun forget(context: Context, name: String) {
        prefs(context).edit().remove("token:$name").apply { if (lastTv(context) == name) remove("last") }.apply()
        if (tv?.name == name) disconnect()
    }

    private fun deviceId(context: Context): String =
        context.getSharedPreferences("lumiere", Context.MODE_PRIVATE).getString("deviceId", null) ?: "phone"
}
