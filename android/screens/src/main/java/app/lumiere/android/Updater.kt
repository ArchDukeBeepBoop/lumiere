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
    data class Available(val code: Int, val name: String)

    /** The Mac publishes the phone's build only; a Quest is updated by sideloading. */
    suspend fun check(server: Server): Available? = if (AppBuild.quest) null else runCatching {
        val o = JSONObject(server.get("Lumiere/Android/Latest"))
        val code = o.optInt("VersionCode")
        if (code > AppBuild.versionCode) Available(code, o.optString("VersionName")) else null
    }.getOrNull()

    suspend fun install(context: Context, server: Server): String? = withContext(Dispatchers.IO) {
        if (AppBuild.quest) return@withContext "Updates on a Quest are installed from the Mac with adb."
        runCatching {
            val installer = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                server.http.newCall(Request.Builder().url(server.url("Lumiere/Android/lumiere.apk")).build())
                    .execute().use { r ->
                        if (!r.isSuccessful) error("the server answered ${r.code}")
                        session.openWrite("lumiere.apk", 0, -1).use { out -> r.body!!.byteStream().copyTo(out); session.fsync(out) }
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
