package app.lumiere.android

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * The device PIN, kept as a salted hash rather than the digits, and the
 * wait after too many wrong ones. A four-digit PIN can't resist someone
 * with the app's files; this keeps it off a glance at them, and makes
 * guessing at the pad slow.
 */
object PinLock {
    private const val ITERATIONS = 120_000
    /** Wrong PINs allowed before the pad makes you wait. */
    const val FREE_TRIES = 5
    /** The first wait, doubled for each wrong PIN after it. */
    const val FIRST_WAIT_MS = 30_000L

    /** What is stored for [pin]: "pbkdf2$iterations$salt$hash". */
    fun seal(pin: String, salt: ByteArray = ByteArray(16).also { SecureRandom().nextBytes(it) }): String =
        "pbkdf2\$$ITERATIONS\$${b64(salt)}\$${b64(derive(pin, salt, ITERATIONS))}"

    fun matches(stored: String, pin: String): Boolean {
        val parts = stored.split('$')
        if (parts.size != 4 || parts[0] != "pbkdf2") return false
        val iterations = parts[1].toIntOrNull() ?: return false
        val salt = runCatching { Base64.getDecoder().decode(parts[2]) }.getOrNull() ?: return false
        val want = runCatching { Base64.getDecoder().decode(parts[3]) }.getOrNull() ?: return false
        return java.security.MessageDigest.isEqual(derive(pin, salt, iterations), want)
    }

    /** A PIN saved by an earlier version, as its digits. */
    fun isPlain(stored: String): Boolean = stored.isNotEmpty() && stored.all { it.isDigit() }

    /** How long the pad must wait after [failures] wrong PINs in a row, the last at [lastAt]. */
    fun waitMs(failures: Int, lastAt: Long, now: Long): Long {
        if (failures < FREE_TRIES) return 0
        val wait = FIRST_WAIT_MS shl (failures - FREE_TRIES).coerceAtMost(10)
        return (lastAt + wait - now).coerceAtLeast(0)
    }

    private fun derive(pin: String, salt: ByteArray, iterations: Int): ByteArray =
        SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(PBEKeySpec(pin.toCharArray(), salt, iterations, 256)).encoded

    private fun b64(bytes: ByteArray) = Base64.getEncoder().withoutPadding().encodeToString(bytes)
}
