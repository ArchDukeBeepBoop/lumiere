package app.lumiere.android.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.exoplayer.ExoPlayer

/**
 * The film carries on in a small window when you leave the app mid-film —
 * Home, or the Picture-in-Picture button. Phones only; a TV has nowhere else
 * to go.
 */
object PictureInPicture {
    var player: ExoPlayer? = null
    var inPip by mutableStateOf(false)

    fun enter(activity: Activity) {
        if (Build.VERSION.SDK_INT < 26) return
        val p = player ?: return
        val size = p.videoSize
        val ratio = if (size.width > 0 && size.height > 0)
            Rational(size.width, size.height).coerceRatio() else Rational(16, 9)
        runCatching { activity.enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(ratio).build()) }
    }

    /** Android refuses ratios wider than 2.39:1 or taller than 1:2.39. */
    private fun Rational.coerceRatio(): Rational = when {
        toFloat() > 2.39f -> Rational(239, 100)
        toFloat() < 1 / 2.39f -> Rational(100, 239)
        else -> this
    }
}
