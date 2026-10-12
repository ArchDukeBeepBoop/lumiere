package app.lumiere.android.spatial

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * A place's own sound, made as it plays rather than recorded: the cabin's
 * fire crackling over a low draw of air, the lake's water lapping with
 * crickets about you, a cinema's hush before the film, a slow deep drone in
 * space. Each sound comes from where its source is: turn to the fireplace
 * and the fire is before you. Quiet, and only while no film plays.
 *
 * Pure (a seeded generator, no Android), so it's tested without a headset;
 * Ambience plays it.
 */
class Soundscape(private val rate: Int = RATE, seed: Long = 1729L) {
    enum class Scene { CABIN, LAKE, CINEMA, SPACE, CLOUDS, MOON, STATION, CITY, SEA, WINTER, NIGHT }

    private var noise = seed or 1L
    private fun white(): Float {
        // xorshift: fast, and the same every run for a seed.
        noise = noise xor (noise shl 13); noise = noise xor (noise ushr 7); noise = noise xor (noise shl 17)
        return ((noise ushr 40).toInt() and 0xFFFFFF) / 8388608f - 1f
    }

    // Filters and envelopes, kept between blocks so nothing clicks at a block's edge.
    private var low1 = 0f; private var low2 = 0f; private var low3 = 0f
    private var crackle = 0f; private var crackleTone = 0f
    private var swell = 0f
    private var gust = 0f
    private var beep = 0
    private var t = 0L
    private val crickets = listOf(Cricket(4300f, 1.9f, 0.0f), Cricket(4650f, 2.6f, 0.7f), Cricket(4480f, 3.3f, 1.6f))

    /** A cricket at [pitch] Hz singing every [every] seconds, starting [offset] in. */
    private class Cricket(val pitch: Float, val every: Float, val offset: Float) { var phase = 0.0 }

    /**
     * Fills [out] (interleaved stereo, -1..1) with [scene], [turn] radians
     * between where you face and the seat's facing (positive: turned left),
     * at [gain]. Silence for no scene.
     */
    fun render(out: FloatArray, scene: Scene?, turn: Float, gain: Float) {
        val frames = out.size / 2
        if (scene == null || gain <= 0f) { out.fill(0f); return }
        for (i in 0 until frames) {
            var l = 0f; var r = 0f
            // In double: a float's seconds lose their fractions within minutes, and the notes go out of tune.
            val seconds = t.toDouble() / rate
            when (scene) {
                Scene.CABIN -> {
                    // The fire: a low roar of air and, now and then, a crack of resin, from the fireplace.
                    low1 += 0.02f * (white() - low1)
                    val roar = low1 * 1.6f
                    if (crackle < 0.002f && white() > 1f - CRACKS_PER_SECOND * 2f / rate) {
                        crackle = 0.25f + 0.75f * abs(white())
                        crackleTone = 0.2f + 0.6f * abs(white())
                    }
                    low2 += crackleTone * (white() - low2)
                    val crack = low2 * crackle
                    crackle *= 0.9985f - 0.004f * crackleTone
                    val (gl, gr) = pan(FIRE_ANGLE - turn)
                    l += (roar + crack) * gl; r += (roar + crack) * gr
                }
                Scene.LAKE -> {
                    // Water lapping at the pontoon: a band of soft noise rising and falling with each small wave.
                    val w = white()
                    low1 += 0.12f * (w - low1); low3 += 0.02f * (w - low3)
                    val water = (low1 - low3) * 1.4f
                    val lap = (0.5 + 0.5 * sin(2 * PI * 0.37 * seconds) * sin(2 * PI * 0.11 * seconds + 1.0)).toFloat()
                    l += water * lap; r += water * (1f - lap * 0.6f)
                    // Crickets about you, each its own chirp: a few quick pulses of a high note.
                    for ((k, c) in crickets.withIndex()) {
                        c.phase = (c.phase + 2 * PI * c.pitch / rate) % (2 * PI)
                        val beat = (seconds + c.offset) % c.every
                        val pulses = if (beat < 0.18) (0.5 + 0.5 * cos(2 * PI * 28 * beat)).toFloat() else 0f
                        val s = sin(c.phase).toFloat() * pulses * 0.08f
                        val (gl, gr) = pan(CRICKET_ANGLES[k] - turn)
                        l += s * gl; r += s * gr
                    }
                }
                Scene.CINEMA -> {
                    // A big hall's hush: air moving, very low.
                    low1 += 0.008f * (white() - low1)
                    low3 += 0.008f * (white() - low3)
                    l += low1 * 1.2f; r += low3 * 1.2f
                }
                Scene.CLOUDS -> {
                    // Wind high up: a broad rush rising and falling in long gusts, a little brighter as it rises.
                    val w = white()
                    low1 += 0.04f * (w - low1); low3 += 0.004f * (w - low3)
                    val g = (0.55 + 0.45 * sin(2 * PI * 0.07 * seconds) * sin(2 * PI * 0.023 * seconds + 0.6)).toFloat()
                    gust += 0.0005f * (g - gust)
                    val air = (low1 - low3) * (0.6f + 1.4f * gust) * 1.3f
                    l += air * (0.8f + 0.2f * sin(2 * PI * 0.05 * seconds).toFloat()); r += air * (0.8f - 0.2f * sin(2 * PI * 0.05 * seconds).toFloat())
                }
                Scene.MOON -> {
                    // No air to carry a sound: only your suit's own quiet hum, and now and then a faint radio click.
                    val hum = (sin(2 * PI * 100 * seconds) * 0.5 + sin(2 * PI * 200 * seconds) * 0.2).toFloat() * 0.02f
                    low1 += 0.05f * (white() - low1)
                    if (crackle < 0.002f && white() > 1f - 0.4f * 2f / rate) crackle = 0.4f
                    crackle *= 0.995f
                    val click = low1 * crackle * 0.6f
                    l += hum + low1 * 0.05f + click; r += hum + low1 * 0.05f + click
                }
                Scene.STATION -> {
                    // A station's air: fans pushing it round, a low electrical hum, and a soft chime now and then.
                    val w = white()
                    low1 += 0.06f * (w - low1); low3 += 0.01f * (w - low3)
                    val fans = (low1 - low3) * 0.9f + low3 * 0.6f
                    val hum = (sin(2 * PI * 60 * seconds) * 0.4 + sin(2 * PI * 120 * seconds) * 0.25).toFloat() * 0.03f
                    if (beep <= 0 && white() > 1f - 0.08f * 2f / rate) beep = (rate * 0.25f).toInt()
                    var chime = 0f
                    if (beep > 0) {
                        val k = 1f - beep / (rate * 0.25f)
                        chime = (sin(2 * PI * 1318.5 * seconds) * (1 - k) * (1 - k)).toFloat() * 0.05f
                        beep--
                    }
                    val (gl, gr) = pan(STATION_CHIME_ANGLE - turn)
                    l += fans + hum + chime * gl; r += fans * 0.95f + hum + chime * gr
                }
                Scene.CITY -> {
                    // A city at night from a roof: the low rumble of traffic far below, swelling and easing, and now and then a horn far off.
                    val w = white()
                    low1 += 0.004f * (w - low1); low3 += 0.03f * (w - low3)
                    val g = (0.7 + 0.3 * sin(2 * PI * 0.05 * seconds) * sin(2 * PI * 0.017 * seconds + 2.0)).toFloat()
                    val rumble = (low1 * 2.2f + (low3 - low1) * 0.25f) * g
                    if (beep <= 0 && white() > 1f - 0.03f * 2f / rate) beep = (rate * 0.6f).toInt()
                    var horn = 0f
                    if (beep > 0) {
                        val k = 1f - beep / (rate * 0.6f)
                        val env = if (k < 0.1f) k * 10f else (1f - k)
                        horn = ((sin(2 * PI * 392.0 * seconds) + 0.5 * sin(2 * PI * 494.0 * seconds)).toFloat() * env * 0.012f)
                        beep--
                    }
                    l += rumble + horn * 0.7f; r += rumble * 0.95f + horn
                }
                Scene.SEA -> {
                    // Under the sea: a deep slow swell all round, and bubbles rising now and then, each a little upward chirp.
                    low1 += 0.002f * (white() - low1); low3 += 0.0008f * (white() - low3)
                    val swellAmp = (0.7 + 0.3 * sin(2 * PI * 0.08 * seconds)).toFloat()
                    val deep = (low1 * 3.0f + low3 * 2.0f) * swellAmp
                    if (beep <= 0 && white() > 1f - 1.5f * 2f / rate) { beep = (rate * 0.05f).toInt(); crackleTone = 600f + 900f * abs(white()) }
                    var bubble = 0f
                    if (beep > 0) {
                        val k = 1f - beep / (rate * 0.05f)
                        bubble = (sin(2 * PI * (crackleTone * (1 + k)) * seconds) * (1 - k)).toFloat() * 0.04f
                        beep--
                    }
                    l += deep + bubble; r += deep * 0.9f + bubble * 0.6f
                }
                Scene.WINTER -> {
                    // The fire, as the cabin's, and the wind round the cabin outside.
                    low1 += 0.02f * (white() - low1)
                    val roar = low1 * 1.4f
                    if (crackle < 0.002f && white() > 1f - CRACKS_PER_SECOND * 2f / rate) {
                        crackle = 0.25f + 0.75f * abs(white()); crackleTone = 0.2f + 0.6f * abs(white())
                    }
                    low2 += crackleTone * (white() - low2)
                    val crack = low2 * crackle
                    crackle *= 0.9985f - 0.004f * crackleTone
                    val (gl, gr) = pan(FIRE_ANGLE - turn)
                    l += (roar + crack) * gl; r += (roar + crack) * gr
                    low3 += 0.003f * (white() - low3)
                    val g = (0.5 + 0.5 * sin(2 * PI * 0.04 * seconds) * sin(2 * PI * 0.013 * seconds + 1.3)).toFloat()
                    gust += 0.0004f * (g - gust)
                    val wind = low3 * (0.6f + 2.0f * gust) * 1.2f
                    l += wind * 0.9f; r += wind
                }
                Scene.NIGHT -> {
                    // A summer field at night: crickets about you, and the faintest breeze.
                    for ((k, c) in crickets.withIndex()) {
                        c.phase = (c.phase + 2 * PI * c.pitch / rate) % (2 * PI)
                        val beat = (seconds + c.offset) % c.every
                        val pulses = if (beat < 0.18) (0.5 + 0.5 * cos(2 * PI * 28 * beat)).toFloat() else 0f
                        val s = sin(c.phase).toFloat() * pulses * 0.08f
                        val (gl, gr) = pan(CRICKET_ANGLES[k] - turn)
                        l += s * gl; r += s * gr
                    }
                    low3 += 0.004f * (white() - low3)
                    l += low3 * 0.4f; r += low3 * 0.4f
                }
                Scene.SPACE -> {
                    // A deep, slow drone, two low notes beating against each other.
                    swell = (0.6 + 0.4 * sin(2 * PI * 0.05 * seconds)).toFloat()
                    val a = (sin(2 * PI * 55 * seconds) + 0.6 * sin(2 * PI * 82.6 * seconds)).toFloat()
                    low1 += 0.01f * (white() - low1)
                    val s = (a * 0.12f + low1 * 0.5f) * swell
                    l += s; r += s * 0.9f
                }
            }
            out[2 * i] = (l * gain).coerceIn(-1f, 1f)
            out[2 * i + 1] = (r * gain).coerceIn(-1f, 1f)
            t++
        }
    }

    companion object {
        const val RATE = 22_050
        /** How often the fire cracks, on average. */
        const val CRACKS_PER_SECOND = 5f
        /** Where the fireplace is from your seat in the cabin: on your left, a little behind. */
        const val FIRE_ANGLE = 1.95f
        /** Where the station's panel that chimes is: behind you, on the back wall. */
        const val STATION_CHIME_ANGLE = 3.0f
        /** Where the crickets are from your seat at the lake: left, behind you, right. */
        val CRICKET_ANGLES = floatArrayOf(1.2f, 2.7f, -1.9f)

        /**
         * How loud a sound [azimuth] radians off where you face is in each
         * ear (positive: to your left): equal power, never quite silent on
         * the far side, a little quieter behind you.
         */
        fun pan(azimuth: Float): Pair<Float, Float> {
            val side = sin(azimuth)
            val behind = if (cos(azimuth) < 0f) 0.8f else 1f
            val left = kotlin.math.sqrt(((1f + side) / 2f).coerceIn(0.05f, 1f)) * behind
            val right = kotlin.math.sqrt(((1f - side) / 2f).coerceIn(0.05f, 1f)) * behind
            return left to right
        }

        /** The place's scene, if it has one: your room has its own sounds, the dark none. */
        fun sceneFor(place: app.lumiere.android.Stage.Place, hall: Boolean): Scene? = when (place) {
            app.lumiere.android.Stage.Place.CABIN -> Scene.CABIN
            app.lumiere.android.Stage.Place.LAKE -> Scene.LAKE
            app.lumiere.android.Stage.Place.CINEMA -> if (hall) Scene.CINEMA else null
            app.lumiere.android.Stage.Place.SPACE -> Scene.SPACE
            app.lumiere.android.Stage.Place.CLOUDS -> Scene.CLOUDS
            app.lumiere.android.Stage.Place.MOON -> Scene.MOON
            app.lumiere.android.Stage.Place.STATION -> Scene.STATION
            app.lumiere.android.Stage.Place.DRIVE_IN -> Scene.NIGHT
            app.lumiere.android.Stage.Place.PALACE -> if (hall) Scene.CINEMA else null
            app.lumiere.android.Stage.Place.ROOFTOP -> Scene.CITY
            app.lumiere.android.Stage.Place.WINTER -> Scene.WINTER
            app.lumiere.android.Stage.Place.SEA -> Scene.SEA
            else -> null
        }

        /** A gain change of at most this much per second, so the sound fades in and out. */
        const val FADE_PER_SECOND = 0.7f

        /** The gain [from] toward [to] after [seconds]. */
        fun fade(from: Float, to: Float, seconds: Float): Float {
            val step = FADE_PER_SECOND * seconds
            return if (to > from) minOf(to, from + step) else maxOf(to, from - step)
        }
    }
}

/**
 * Plays the place's Soundscape on its own quiet stream while you're in a
 * place that has one and no film plays; fades out when one starts, back in
 * when you pause or browse. Started and stopped with the app's window.
 */
class Ambience {
    @Volatile private var scene: Soundscape.Scene? = null
    @Volatile private var target = 0f
    @Volatile private var turn = 0f
    @Volatile private var running = false
    /** Which start the playing thread belongs to: a stop and a quick start never leave two playing. */
    @Volatile private var generation = 0

    /** What to play: the [scene], whether it's [wanted] now (no film playing), and how far you've [turned] from your seat. */
    fun set(scene: Soundscape.Scene?, wanted: Boolean, turned: Float) {
        if (scene != this.scene && scene != null) this.scene = scene
        target = if (wanted && scene != null) VOLUME else 0f
        turn = turned
    }

    fun start() {
        if (running) return
        running = true
        val mine = ++generation
        Thread({ play(mine) }, "lumiere-ambience").apply { isDaemon = true; start() }
    }

    fun stop() {
        running = false
        generation++
    }

    private fun play(mine: Int) {
        val rate = Soundscape.RATE
        val frames = 1024
        val track = runCatching {
            android.media.AudioTrack.Builder()
                .setAudioAttributes(android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_GAME)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(android.media.AudioFormat.Builder()
                    .setEncoding(android.media.AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(rate)
                    .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_STEREO).build())
                .setBufferSizeInBytes(frames * 2 * 4 * 4)
                .setTransferMode(android.media.AudioTrack.MODE_STREAM)
                .build()
        }.getOrNull() ?: return
        val synth = Soundscape(rate)
        val block = FloatArray(frames * 2)
        var gain = 0f
        var playing = false
        try {
            while (running && generation == mine) {
                val to = target
                gain = Soundscape.fade(gain, to, frames.toFloat() / rate)
                if (gain <= 0f && to <= 0f) {
                    // Nothing to hear: rest, rather than write silence.
                    if (playing) { track.pause(); track.flush(); playing = false }
                    Thread.sleep(120)
                    continue
                }
                if (!playing) { track.play(); playing = true }
                synth.render(block, scene, turn, gain)
                track.write(block, 0, block.size, android.media.AudioTrack.WRITE_BLOCKING)
            }
        } catch (_: Throwable) {
        } finally {
            runCatching { track.stop() }
            track.release()
        }
    }

    companion object {
        /** Quiet: a place's sound is felt more than heard, under your browsing and the window's own sounds. */
        const val VOLUME = 0.22f
    }
}

/** The angle you've turned from the seat's facing, in radians, positive to your left. */
fun turnedFrom(facing: com.meta.spatial.core.Quaternion, look: com.meta.spatial.core.Vector3): Float {
    val ahead = facing * com.meta.spatial.core.Vector3(0f, 0f, 1f)
    val left = facing * com.meta.spatial.core.Vector3(1f, 0f, 0f)
    val a = look.x * ahead.x + look.z * ahead.z
    val s = look.x * left.x + look.z * left.z
    if (a == 0f && s == 0f) return 0f
    return kotlin.math.atan2(s, a)
}
