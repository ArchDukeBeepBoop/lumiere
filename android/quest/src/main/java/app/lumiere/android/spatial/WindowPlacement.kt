package app.lumiere.android.spatial

import com.meta.spatial.core.Pose
import com.meta.spatial.core.Quaternion
import com.meta.spatial.core.Vector3

/**
 * Where the window comes before you while you browse. In your room, as any
 * Quest window: [Window.DISTANCE_M] off, its middle just under your eyes.
 * Away from it — the cinema, the dark, space — lower and a little nearer,
 * tipped back to face your eyes as a tablet on your lap is, so the big
 * screen beyond, showing the title you're on, stays in view above it, as
 * Bigscreen's menu does. Pure, so it's tested without a headset.
 */
object WindowPlacement {
    /** The window's pose for your [eye], looking along [forward] (level, normalised), turned [facing]. */
    fun pose(eye: Vector3, forward: Vector3, facing: Quaternion, away: Boolean): Pose {
        if (!away) {
            val at = eye + forward * Window.DISTANCE_M
            return Pose(Vector3(at.x, eye.y - Window.BELOW_EYES_M, at.z), facing)
        }
        val at = eye + forward * Window.AWAY_DISTANCE_M - Vector3(0f, Window.AWAY_BELOW_EYES_M, 0f)
        return Pose(at, Quaternion.fromDirection((at - eye).normalize()))
    }
}
