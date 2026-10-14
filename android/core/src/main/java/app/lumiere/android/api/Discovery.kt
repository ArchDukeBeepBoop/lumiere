package app.lumiere.android.api

import android.content.Context
import android.net.wifi.WifiManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException

data class FoundServer(val name: String, val address: String, val id: String)

/**
 * The address the sign-in screen should hold once discovery has run: the one
 * already saved while it still answers or is among those found, else the one
 * server found. A saved address goes stale when the Mac's address changes or
 * a wrong one was typed, and was kept even with the right server listed.
 */
fun preferredAddress(saved: String?, found: List<FoundServer>, savedAnswers: Boolean): String? {
    val same = { a: String, b: String -> a.trim().trimEnd('/').equals(b.trim().trimEnd('/'), ignoreCase = true) }
    if (saved != null && (savedAnswers || found.any { same(it.address, saved) })) return saved
    return found.singleOrNull()?.address ?: saved
}

/**
 * Jellyfin's discovery: "who is JellyfinServer?" broadcast on UDP 7359, and
 * every server on the network answers with its address. The Lumiere server
 * answers once "Share on my home network" is on in the Mac app's Settings.
 */
object Discovery {
    suspend fun find(context: Context, waitMillis: Int = 2500): List<FoundServer> = withContext(Dispatchers.IO) {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifi.createMulticastLock("lumiere-discovery").apply { setReferenceCounted(false); acquire() }
        val found = linkedMapOf<String, FoundServer>()
        try {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                socket.soTimeout = 400
                val ask = "who is JellyfinServer?".toByteArray()
                socket.send(DatagramPacket(ask, ask.size, InetAddress.getByName("255.255.255.255"), 7359))
                val deadline = System.currentTimeMillis() + waitMillis
                val buffer = ByteArray(2048)
                while (System.currentTimeMillis() < deadline) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                    } catch (_: SocketTimeoutException) {
                        continue
                    }
                    runCatching {
                        val o = JSONObject(String(packet.data, 0, packet.length))
                        val server = FoundServer(o.optString("Name"), o.optString("Address"), o.optString("Id"))
                        if (server.address.isNotEmpty()) found[server.id + server.address] = server
                    }
                }
            }
        } catch (_: Exception) {
            // No network, or broadcasts blocked: an empty list, and the address
            // can still be typed in.
        } finally {
            lock.release()
        }
        found.values.toList().ifEmpty { scan(context) }
    }

    /**
     * When nothing answers the broadcast — a VPN on the phone, or a router
     * that drops broadcasts — ask each address on the phone's own Wi-Fi
     * network for a server on Lumiere's port. Over the Wi-Fi network itself,
     * so a VPN does not carry the questions off the house.
     */
    suspend fun scan(context: Context, port: Int = 8098): List<FoundServer> = withContext(Dispatchers.IO) {
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        @Suppress("DEPRECATION")
        val wifi = connectivity.allNetworks.firstOrNull { n ->
            connectivity.getNetworkCapabilities(n)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true ||
                connectivity.getNetworkCapabilities(n)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) == true
        } ?: return@withContext emptyList()
        val own = connectivity.getLinkProperties(wifi)?.linkAddresses
            ?.firstOrNull { it.address is java.net.Inet4Address }?.address?.address ?: return@withContext emptyList()
        val client = okhttp3.OkHttpClient.Builder()
            .socketFactory(wifi.socketFactory)
            .connectTimeout(700, java.util.concurrent.TimeUnit.MILLISECONDS)
            .readTimeout(1500, java.util.concurrent.TimeUnit.MILLISECONDS)
            .build()
        val hosts = hostsAround(own)
        val found = java.util.concurrent.ConcurrentLinkedQueue<FoundServer>()
        coroutineScope {
            hosts.chunked(64).forEach { batch ->
                batch.map { host ->
                    async {
                        val address = "http://$host:$port"
                        runCatching {
                            client.newCall(okhttp3.Request.Builder().url("$address/System/Info/Public").build())
                                .execute().use { r ->
                                    if (r.isSuccessful) {
                                        val o = JSONObject(r.body!!.string())
                                        found += FoundServer(o.optString("ServerName", "Lumiere"), address, o.optString("Id"))
                                    }
                                }
                        }
                    }
                }.forEach { it.await() }
                if (found.isNotEmpty()) return@coroutineScope
            }
        }
        found.distinctBy { it.id }
    }

    /** Every other address in the phone's /24 — a home network's usual size. */
    fun hostsAround(own: ByteArray): List<String> {
        val base = own.take(3).joinToString(".") { (it.toInt() and 0xff).toString() }
        val mine = own[3].toInt() and 0xff
        return (1..254).filter { it != mine }.map { "$base.$it" }
    }
}
