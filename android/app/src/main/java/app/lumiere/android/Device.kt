package app.lumiere.android

import android.app.ActivityManager
import android.content.Context

/**
 * What this device can afford. A projector with 2 GB gets smaller artwork,
 * a smaller picture cache, a shorter read-ahead and calmer animation —
 * Apple's way of keeping the Apple TV app smooth on its oldest boxes.
 */
object Device {
    /** Less than 3 GB of memory, or Android's own low-memory flag. */
    var lowMemory = false
        private set
    var totalMb = 0L
        private set

    private var app: Context? = null

    fun detect(context: Context) {
        app = context.applicationContext
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        totalMb = info.totalMem / 1_048_576
        lowMemory = am.isLowRamDevice || totalMb < 3_000
    }

    /** Artwork width to ask the server for: three fifths of it on a low-memory device — the projector's screen shows no difference. */
    fun artWidth(width: Int): Int = if (lowMemory) (width * 3 / 5).coerceAtLeast(120) else width

    /** Connected by cable rather than Wi-Fi, checked when asked. */
    val wired: Boolean get() = runCatching {
        val cm = app?.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
        cm?.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) == true
    }.getOrDefault(false)
}

/** Reduce Motion as it stands, for code with no settings to hand. Set by the activity. */
object Motion {
    private val state = androidx.compose.runtime.mutableStateOf(false)
    var reduced: Boolean get() = state.value
        set(v) { state.value = v }
    /** An animation's length, or none when motion is reduced. */
    fun ms(normal: Int) = if (reduced) 0 else normal
}
