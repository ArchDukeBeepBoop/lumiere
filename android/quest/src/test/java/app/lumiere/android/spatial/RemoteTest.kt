package app.lumiere.android.spatial

import android.view.KeyEvent
import com.meta.spatial.runtime.ButtonBits
import org.junit.Assert.assertEquals
import org.junit.Test

class RemoteTest {
    @Test fun eitherStickIsTheArrows() {
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_LEFT), Remote.keysFor(ButtonBits.ButtonThumbLL, false))
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_RIGHT), Remote.keysFor(ButtonBits.ButtonThumbRR, true))
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_UP), Remote.keysFor(ButtonBits.ButtonThumbRU, false))
    }

    @Test fun aIsOkOrPlayPause() {
        assertEquals(listOf(KeyEvent.KEYCODE_DPAD_CENTER), Remote.keysFor(ButtonBits.ButtonA, inPlayer = false))
        assertEquals(listOf(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE), Remote.keysFor(ButtonBits.ButtonX, inPlayer = true))
    }

    @Test fun bIsBackAndAStickClickIsMenu() {
        assertEquals(listOf(KeyEvent.KEYCODE_BACK), Remote.keysFor(ButtonBits.ButtonY, false))
        assertEquals(listOf(KeyEvent.KEYCODE_MENU), Remote.keysFor(ButtonBits.ButtonThumbRClick, false))
    }

    @Test fun triggersAndGripsAreLeftAlone() =
        assertEquals(emptyList<Int>(), Remote.keysFor(ButtonBits.ButtonTriggerR or ButtonBits.ButtonSqueezeL, false))
}

class RemoteRoutingTest {
    @org.junit.After fun tidy() { app.lumiere.android.ui.PosterWall.open = false; app.lumiere.android.OpenApp.press = null }

    @org.junit.Test fun withTheWallUpKeysAreTheWallsAndNeverTheHiddenWindows() {
        val pressed = mutableListOf<Int>()
        app.lumiere.android.OpenApp.press = { pressed += it }
        val wall = app.lumiere.android.ui.PosterWall
        wall.open = true
        val before = wall.nudges
        Remote.deliver(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
        org.junit.Assert.assertEquals(before + 1, wall.nudges)
        org.junit.Assert.assertEquals(1, wall.lastNudge)
        Remote.deliver(android.view.KeyEvent.KEYCODE_DPAD_CENTER)
        org.junit.Assert.assertTrue("OK never reaches the hidden window", pressed.isEmpty())
        Remote.deliver(android.view.KeyEvent.KEYCODE_BACK)
        org.junit.Assert.assertFalse("B puts the wall away", wall.open)
        Remote.deliver(android.view.KeyEvent.KEYCODE_DPAD_CENTER)
        org.junit.Assert.assertEquals(listOf(android.view.KeyEvent.KEYCODE_DPAD_CENTER), pressed)
    }
}
