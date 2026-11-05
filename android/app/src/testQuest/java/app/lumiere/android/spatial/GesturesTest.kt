package app.lumiere.android.spatial

import android.view.KeyEvent
import com.meta.spatial.runtime.MicrogestureBits
import org.junit.Assert.assertEquals
import org.junit.Test

class GesturesTest {
    @Test fun aThumbTapIsOkOrPlayPause() {
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_CENTER), Gestures.keysFor(MicrogestureBits.RightMicrogestureTapThumb, false))
        assertEquals(listOf(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE), Gestures.keysFor(MicrogestureBits.LeftMicrogestureTapThumb, true))
    }

    @Test fun swipesAreTheArrows() {
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_LEFT), Gestures.keysFor(MicrogestureBits.RightMicrogestureSwipeLeft, true))
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_RIGHT), Gestures.keysFor(MicrogestureBits.LeftMicrogestureSwipeRight, true))
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_UP), Gestures.keysFor(MicrogestureBits.RightMicrogestureSwipeForward, false))
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_DOWN), Gestures.keysFor(MicrogestureBits.LeftMicrogestureSwipeBack, false))
    }
}
