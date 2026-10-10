package app.lumiere.android.spatial

import android.view.KeyEvent
import app.lumiere.android.OpenApp
import app.lumiere.android.Screen
import com.meta.spatial.core.Query
import com.meta.spatial.core.SystemBase
import com.meta.spatial.runtime.ButtonBits
import com.meta.spatial.toolkit.Controller

/**
 * The Quest's controllers as Lumiere's TV remote, so everything the remote
 * does works from them too. Either thumbstick moves the focus (and in a film
 * skips, as left and right do on the remote); A or X is OK, or play and
 * pause in a film; B or Y goes back; a thumbstick click is the remote's Menu,
 * a title's actions. Held, a direction repeats. The triggers stay pointers
 * and the grips still carry the window.
 */
class Remote : SystemBase() {
    private var held = 0
    private var heldSince = 0L
    private var lastRepeat = 0L

    override fun execute() {
        val press = OpenApp.press ?: return
        var down = 0
        for (e in Query.where { has(Controller.id) }.eval()) {
            val c = e.getComponent<Controller>()
            if (c.isActive) down = down or c.buttonState
        }
        val now = System.currentTimeMillis()
        val inPlayer = OpenApp.state?.top is Screen.Player
        val fresh = down and held.inv()
        keysFor(fresh, inPlayer).forEach(press)
        if (fresh != 0) { heldSince = now; lastRepeat = now }
        // A direction held: again after 0.45 s, then every 0.14 s.
        val dirs = down and DIRECTIONS
        if (dirs != 0 && fresh and DIRECTIONS == 0 && now - heldSince > 450 && now - lastRepeat > 140) {
            lastRepeat = now
            keysFor(dirs, inPlayer).forEach(press)
        }
        held = down
    }

    companion object {
        private val UP = ButtonBits.ButtonThumbLU or ButtonBits.ButtonThumbRU
        private val DOWN = ButtonBits.ButtonThumbLD or ButtonBits.ButtonThumbRD
        private val LEFT = ButtonBits.ButtonThumbLL or ButtonBits.ButtonThumbRL
        private val RIGHT = ButtonBits.ButtonThumbLR or ButtonBits.ButtonThumbRR
        private val DIRECTIONS = UP or DOWN or LEFT or RIGHT

        /** The remote keys newly pressed [bits] stand for. */
        fun keysFor(bits: Int, inPlayer: Boolean): List<Int> = buildList {
            if (bits and UP != 0) add(KeyEvent.KEYCODE_DPAD_UP)
            if (bits and DOWN != 0) add(KeyEvent.KEYCODE_DPAD_DOWN)
            if (bits and LEFT != 0) add(KeyEvent.KEYCODE_DPAD_LEFT)
            if (bits and RIGHT != 0) add(KeyEvent.KEYCODE_DPAD_RIGHT)
            if (bits and (ButtonBits.ButtonA or ButtonBits.ButtonX) != 0)
                add(if (inPlayer) KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE else KeyEvent.KEYCODE_DPAD_CENTER)
            if (bits and (ButtonBits.ButtonB or ButtonBits.ButtonY) != 0) add(KeyEvent.KEYCODE_BACK)
            if (bits and (ButtonBits.ButtonThumbLClick or ButtonBits.ButtonThumbRClick) != 0) add(KeyEvent.KEYCODE_MENU)
        }
    }
}
