package app.lumiere.android.spatial

import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import app.lumiere.android.player.ScreenAudio
import app.lumiere.android.player.Surround
import com.meta.spatial.core.Entity
import com.meta.spatial.core.SystemBase
import com.meta.spatial.core.Vector3
import com.meta.spatial.runtime.Scene
import com.meta.spatial.toolkit.Transform

/**
 * Each frame of a film, where the screen is from your head, for the
 * player's sound to lean that way (ScreenAudio). Measured in your head's
 * own frame, so it holds lying down as well as sitting up. Outside the
 * player, and in a 360° film whose sound is already all round you, the
 * sound is left straight ahead.
 */
class ScreenSound(private val scene: Scene, private val screen: Entity) : SystemBase() {
    override fun execute() {
        if (!ScreenAudio.enabled) return
        runCatching {
            if (OpenApp.state?.top !is Screen.Player || Surround.active) { ScreenAudio.azimuth = 0f; return }
            val head = scene.getViewerPose()
            val to = screen.getComponent<Transform>().transform.t - head.t
            ScreenAudio.azimuth = azimuth(to, head.q * Vector3(0f, 0f, 1f), head.q * Vector3(1f, 0f, 0f))
        }
    }

    companion object {
        /**
         * The angle to [to] from [forward], in radians, positive towards [left]
         * (you face +Z and your left is +X); 0 when it's straight ahead.
         */
        fun azimuth(to: Vector3, forward: Vector3, left: Vector3): Float {
            val ahead = to.x * forward.x + to.y * forward.y + to.z * forward.z
            val side = to.x * left.x + to.y * left.y + to.z * left.z
            if (ahead == 0f && side == 0f) return 0f
            return kotlin.math.atan2(side, ahead)
        }
    }
}
