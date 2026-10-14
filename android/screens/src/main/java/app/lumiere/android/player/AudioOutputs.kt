package app.lumiere.android.player

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.exoplayer.ExoPlayer

/**
 * Where the sound goes: the headset's own speakers, Bluetooth headphones or
 * a speaker, a USB or wired set. The one you choose is asked of the film's
 * player and the music's (ExoPlayer's preferred device), and remembered by
 * its name, so your headphones are chosen again when they reconnect; if it
 * isn't there, the system's own choice stands.
 */
object AudioOutputs {
    data class Output(val id: Int, val name: String, val kind: Kind)
    enum class Kind { HEADSET, BLUETOOTH, WIRED, USB, OTHER }

    /** The chosen output's name; null for the system's own choice. */
    var chosen by mutableStateOf<String?>(null)
        private set
    /** Bumped when outputs come or go, for lists to refresh. */
    var changes by mutableStateOf(0)
        private set

    private var watching = false

    fun init(context: Context) {
        val app = context.applicationContext
        if (chosen == null) chosen = app.getSharedPreferences("lumiere", Context.MODE_PRIVATE).getString("audioOutput", null)
        if (watching) return
        watching = true
        runCatching {
            (app.getSystemService(Context.AUDIO_SERVICE) as AudioManager).registerAudioDeviceCallback(object : android.media.AudioDeviceCallback() {
                override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) { changes++; applyAll(app) }
                override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) { changes++ }
            }, android.os.Handler(android.os.Looper.getMainLooper()))
        }
    }

    /** Every output the sound could go to now, the headset's own first; one of each name. */
    fun list(context: Context): List<Output> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).mapNotNull { d ->
            val kind = kindOf(d.type) ?: return@mapNotNull null
            val name = when (kind) {
                Kind.HEADSET -> "This headset's speakers"
                else -> d.productName?.toString()?.takeIf { it.isNotBlank() && !it.equals(android.os.Build.MODEL, true) }
                    ?: when (kind) { Kind.BLUETOOTH -> "Bluetooth"; Kind.WIRED -> "Headphones"; Kind.USB -> "USB audio"; else -> "Other" }
            }
            Output(d.id, name, kind)
        }.distinctBy { it.name }.sortedBy { it.kind.ordinal }
    }

    private fun kindOf(type: Int): Kind? = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> Kind.HEADSET
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER -> Kind.BLUETOOTH
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> Kind.WIRED
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> Kind.USB
        else -> null
    }

    /** [output] chosen (null: the system's choice), for every player now and later. */
    fun choose(context: Context, output: Output?) {
        chosen = output?.name
        context.applicationContext.getSharedPreferences("lumiere", Context.MODE_PRIVATE).edit().apply {
            if (output == null) remove("audioOutput") else putString("audioOutput", output.name)
        }.apply()
        applyAll(context)
        app.lumiere.android.Probe.info("sound", "output chosen", output?.let { "${it.name} (${it.kind}, device ${it.id})" } ?: "the system's own choice")
    }

    /** The players asked to use the chosen output. */
    private val players = java.util.Collections.newSetFromMap(java.util.WeakHashMap<ExoPlayer, Boolean>())

    /** [player] follows the chosen output from now on. */
    fun attach(context: Context, player: ExoPlayer) {
        init(context)
        players += player
        apply(context, player)
    }

    private fun applyAll(context: Context) = players.toList().forEach { apply(context, it) }

    private fun apply(context: Context, player: ExoPlayer) {
        val name = chosen
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val device = if (name == null) null else am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { d ->
            list(context).firstOrNull { it.id == d.id }?.name == name
        }
        runCatching { player.setPreferredAudioDevice(device) }
            .onSuccess {
                app.lumiere.android.Probe.report("sound", "output applied",
                    if (name != null && device == null) app.lumiere.android.Probe.Status.WARN else app.lumiere.android.Probe.Status.OK,
                    if (name == null) "the system's choice, for ${players.size} player(s)"
                    else if (device == null) "\"$name\" chosen but not connected now: the system's choice stands"
                    else "\"$name\" asked of ${players.size} player(s)")
            }
            .onFailure { app.lumiere.android.Probe.fail("sound", "output applied", "the player refused the output: ${app.lumiere.android.Probe.why(it)}") }
    }

    /** The headset's Bluetooth settings, to pair something new. */
    fun pairNew(context: Context) {
        runCatching {
            context.startActivity(android.content.Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
