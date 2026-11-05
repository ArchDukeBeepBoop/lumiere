package app.lumiere.android.spatial

import com.meta.spatial.core.Vector3

/**
 * Whether the view jumped as a Reset View moves it: half a metre or more, or
 * a turn of 50° or more, between two looks a tenth of a second apart. A head
 * turns at most about 200° a second in a quick look, so 20° a tick; walking
 * moves it centimetres. Pure, so it's tested without a headset.
 */
object ResetWatch {
    const val JUMP_M = 0.5f
    const val TURN_DEGREES = 50f

    fun isReset(wasAt: Vector3, wasAhead: Vector3, at: Vector3, ahead: Vector3): Boolean {
        val dx = at.x - wasAt.x; val dz = at.z - wasAt.z
        if (dx * dx + dz * dz >= JUMP_M * JUMP_M) return true
        val dot = (wasAhead.x * ahead.x + wasAhead.z * ahead.z).coerceIn(-1f, 1f)
        return Math.toDegrees(kotlin.math.acos(dot).toDouble()) >= TURN_DEGREES
    }
}
