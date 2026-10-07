package app.lumiere.android

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

/**
 * Opening the private room: the phone's own lock — fingerprint, face or the
 * screen PIN — as the Mac asks for Touch ID or its password. Like the Mac's,
 * this keeps the libraries out of sight on a screen other people can see; it
 * is not encryption, and says so in Settings.
 */
object Room {
    const val CONFIRM_REQUEST = 7401
    private var pending: ((Boolean) -> Unit)? = null

    fun unlock(activity: Activity, onResult: (Boolean) -> Unit) {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        // A phone with no lock at all has nothing to ask for.
        if (!keyguard.isDeviceSecure) return onResult(true)
        when {
            Build.VERSION.SDK_INT >= 30 -> prompt(activity, onResult) {
                setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            }
            Build.VERSION.SDK_INT >= 28 -> prompt(activity, onResult) {
                @Suppress("DEPRECATION") setDeviceCredentialAllowed(true)
            }
            else -> {
                @Suppress("DEPRECATION")
                val intent = keyguard.createConfirmDeviceCredentialIntent("Private room", null)
                    ?: return onResult(true)
                pending = onResult
                @Suppress("DEPRECATION") activity.startActivityForResult(intent, CONFIRM_REQUEST)
            }
        }
    }

    /** From the activity's onActivityResult, for the pre-Android 9 path. */
    fun confirmed(ok: Boolean) {
        pending?.invoke(ok)
        pending = null
    }

    private fun prompt(activity: Activity, onResult: (Boolean) -> Unit, allow: BiometricPrompt.Builder.() -> Unit) {
        if (Build.VERSION.SDK_INT < 28) return
        val prompt = BiometricPrompt.Builder(activity)
            .setTitle("Private room")
            .setSubtitle("Unlock to show your private libraries")
            .apply(allow)
            .build()
        prompt.authenticate(CancellationSignal(), activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(true)
                override fun onAuthenticationError(code: Int, message: CharSequence) = onResult(false)
            })
    }
}
