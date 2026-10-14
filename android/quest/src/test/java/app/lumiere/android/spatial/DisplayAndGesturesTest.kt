package app.lumiere.android.spatial

import android.view.KeyEvent
import com.meta.spatial.runtime.MicrogestureBits
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DisplayAndGesturesTest {
    @Test fun filmsGetARateThatFitsTheirFrames() {
        assertEquals(72f, Display.rateFor(23.976f))
        assertEquals(72f, Display.rateFor(24f))
        assertEquals(90f, Display.rateFor(29.97f))
        assertEquals(120f, Display.rateFor(59.94f))
        assertEquals("25 fps: nothing fits, the headset keeps its own", 0f, Display.rateFor(25f))
        assertEquals(0f, Display.rateFor(0f))
    }

    @Test fun lookingUpPastThirtyDegreesTiltsTheScreen() {
        assertTrue(Display.lookingUp(0.7f))
        assertFalse(Display.lookingUp(0.2f))
    }

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
