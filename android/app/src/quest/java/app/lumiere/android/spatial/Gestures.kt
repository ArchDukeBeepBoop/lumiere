package app.lumiere.android.spatial

import android.view.KeyEvent
import com.meta.spatial.runtime.MicrogestureBits

/**
 * Hands without controllers: the Quest's microgestures, a thumb against the
 * side of the index finger, as the remote. A tap is OK, or play and pause in
 * a film; swipes left and right are the remote's left and right (skipping in
 * a film); forward and back are up and down.
 */
object Gestures {
    private val TAP = MicrogestureBits.LeftMicrogestureTapThumb or MicrogestureBits.RightMicrogestureTapThumb
    private val LEFT = MicrogestureBits.LeftMicrogestureSwipeLeft or MicrogestureBits.RightMicrogestureSwipeLeft
    private val RIGHT = MicrogestureBits.LeftMicrogestureSwipeRight or MicrogestureBits.RightMicrogestureSwipeRight
    private val FORWARD = MicrogestureBits.LeftMicrogestureSwipeForward or MicrogestureBits.RightMicrogestureSwipeForward
    private val BACK = MicrogestureBits.LeftMicrogestureSwipeBack or MicrogestureBits.RightMicrogestureSwipeBack

    fun keysFor(gesture: Int, inPlayer: Boolean): List<Int> = buildList {
        if (gesture and TAP != 0) add(if (inPlayer) KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE else KeyEvent.KEYCODE_DPAD_CENTER)
        if (gesture and LEFT != 0) add(KeyEvent.KEYCODE_DPAD_LEFT)
        if (gesture and RIGHT != 0) add(KeyEvent.KEYCODE_DPAD_RIGHT)
        if (gesture and FORWARD != 0) add(KeyEvent.KEYCODE_DPAD_UP)
        if (gesture and BACK != 0) add(KeyEvent.KEYCODE_DPAD_DOWN)
    }
}
