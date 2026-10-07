package app.lumiere.android.tv

import app.lumiere.android.api.Server
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * Waking a sleeping Mac: the standard wake-on-LAN packet — six 0xFF bytes,
 * then the Mac's hardware address sixteen times — broadcast on the home
 * network. The Mac must allow it (System Settings › Energy › Wake for
 * network access); the address is learned while the Mac is awake.
 */
object Wake {
    /** Remembers the Mac's address from the server, while it answers. */
    suspend fun learn(server: Server): String? = runCatching {
        JSONObject(server.get("Lumiere/Server")).optString("WakeAddress").ifEmpty { null }
    }.getOrNull()

    suspend fun send(address: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val mac = address.split(':', '-').map { it.toInt(16).toByte() }
            require(mac.size == 6)
            val packet = ByteArray(6) { 0xFF.toByte() } + (0 until 16).flatMap { mac }.toByteArray()
            DatagramSocket().use { s ->
                s.broadcast = true
                for (port in listOf(9, 7)) s.send(DatagramPacket(packet, packet.size, InetAddress.getByName("255.255.255.255"), port))
            }
        }.isSuccess
    }
}
