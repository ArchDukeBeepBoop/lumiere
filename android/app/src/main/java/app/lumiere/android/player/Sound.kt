package app.lumiere.android.player

import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.LoudnessEnhancer
import android.os.Build

/**
 * Small projector speakers lose dialogue: a loudness boost, and night sound,
 * which squeezes the gap between explosions and speech so neither wakes the
 * house nor gets lost. Both on the player's own audio session only.
 */
class Sound {
    private var session = 0
    private var boost: LoudnessEnhancer? = null
    private var night: DynamicsProcessing? = null

    fun apply(audioSession: Int, boostDb: Int, nightOn: Boolean) {
        if (audioSession == 0) return
        if (audioSession != session) release()
        session = audioSession
        runCatching {
            if (boostDb > 0) {
                val b = boost ?: LoudnessEnhancer(audioSession).also { boost = it }
                b.setTargetGain(boostDb * 100)
                b.enabled = true
            } else boost?.enabled = false
        }
        if (Build.VERSION.SDK_INT >= 28) runCatching {
            if (nightOn) {
                val d = night ?: DynamicsProcessing(0, audioSession, null).also { night = it }
                for (ch in 0 until 2) {
                    d.setLimiterByChannelIndex(ch, DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -10f, 0f))
                    d.setPreEqBandAllChannelsTo(0, DynamicsProcessing.EqBand(true, 20000f, 6f))
                }
                d.enabled = true
            } else night?.enabled = false
        }
    }

    fun release() {
        runCatching { boost?.release() }; boost = null
        runCatching { night?.release() }; night = null
    }
}
