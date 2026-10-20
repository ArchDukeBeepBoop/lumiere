package app.lumiere.android

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import app.lumiere.android.api.Server
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONObject

/**
 * A newer Lumiere, from the Mac. The Mac's build is placed beside the server
 * (Scripts/publish.sh); the app asks for its version and, when newer, fetches
 * it with the signed-in client and hands it to Android's installer, which asks
 * before installing. The projector has no other way to be updated.
 */
object Updater {
    data class Available(val code: Int, val name: String, val sha256: String = "")

    /**
     * Each app fetches only its own build: the TV's where the Mac has always
     * kept it, the phone's and the Quest's under their own names — so a phone
     * is never offered the TV's app.
     */
    private val channel = if (Flavor.tv) "" else "${BuildConfig.DEVICE}/"

    suspend fun check(server: Server): Available? = runCatching {
        val o = JSONObject(server.get("Lumiere/Android/${channel}Latest"))
        val code = o.optInt("VersionCode")
        if (code > BuildConfig.VERSION_CODE) Available(code, o.optString("VersionName"), o.optString("Sha256")) else null
    }.getOrNull()

    /**
     * Fetches and installs the update. The download is checked against the
     * SHA-256 the Mac published with it before Android is handed anything: a
     * cut-off or altered file is refused here, not half-installed.
     */
    suspend fun install(context: Context, server: Server): String? = withContext(Dispatchers.IO) {
        val expected = check(server)?.sha256.orEmpty().lowercase()
        runCatching {
            val installer = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                server.http.newCall(Request.Builder().url(server.url("Lumiere/Android/${channel}lumiere.apk")).build())
                    .execute().use { r ->
                        if (!r.isSuccessful) error("the server answered ${r.code}")
                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                        session.openWrite("lumiere.apk", 0, -1).use { out ->
                            java.security.DigestInputStream(r.body!!.byteStream(), digest).copyTo(out)
                            session.fsync(out)
                        }
                        val got = digest.digest().joinToString("") { "%02x".format(it) }
                        if (expected.isNotEmpty() && got != expected) {
                            session.abandon()
                            error("the download did not match the Mac's copy; nothing was installed")
                        }
                    }
                val done = PendingIntent.getBroadcast(context, 0, Intent(context, InstallResult::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                session.commit(done.intentSender)
            }
            null
        }.getOrElse { it.message ?: "couldn't fetch the update" }
    }
}

/** Android's answer: usually "ask the person", which opens its confirmation. */
class InstallResult : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            PackageInstaller.STATUS_SUCCESS -> Diagnostics.note("update installed")
            else -> Diagnostics.note("update failed: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}")
        }
    }
}
