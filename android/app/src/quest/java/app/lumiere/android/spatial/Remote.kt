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
 * a title's actions. Held, a direction repeats. Up and down outside a film
 * scroll the page smoothly instead of hopping card to card. The triggers stay
 * pointers and the grips still carry the window.
 */
class Remote : SystemBase() {
    private var held = 0
    private var heldSince = 0L
    private var lastRepeat = 0L
    private var scrollSince = 0L

    override fun execute() {
        // Called from the SDK's own frame loop, where a failure would stop the app: guarded.
        runCatching { read() }.onFailure { android.util.Log.w("Lumiere", "remote", it) }
    }

    private fun read() {
        if (OpenApp.press == null) return
        var down = 0
        for (e in Query.where { has(Controller.id) }.eval()) {
            val c = e.getComponent<Controller>()
            if (c.isActive) down = down or c.buttonState
        }
        val now = System.currentTimeMillis()
        if (down != 0) FilmBar.wake()
        val inPlayer = OpenApp.state?.top is Screen.Player
        // Faster the longer it's held, as a trackpad's.
        val scrolls = !inPlayer && OpenApp.scroll != null
        val vertical = down and (UP or DOWN)
        if (scrolls && vertical != 0) {
            if (scrollSince == 0L) scrollSince = now
            val ramp = ((now - scrollSince) / 700f).coerceIn(0f, 1f)
            val step = 0.035f + 0.16f * ramp * ramp
            OpenApp.scroll?.invoke(if (vertical and UP != 0) step else -step)
        } else scrollSince = 0L
        val keyBits = if (scrolls) down and (UP or DOWN).inv() else down
        val fresh = keyBits and held.inv()
        keysFor(fresh, inPlayer).forEach(::deliver)
        if (fresh != 0) { heldSince = now; lastRepeat = now }
        // A direction held: again after 0.45 s, then every 0.14 s.
        val dirs = keyBits and DIRECTIONS
        if (dirs != 0 && fresh and DIRECTIONS == 0 && now - heldSince > 450 && now - lastRepeat > 140) {
            lastRepeat = now
            keysFor(dirs, inPlayer).forEach(::deliver)
        }
        held = keyBits
    }

    companion object {
        /** A key from the controllers or the hands, pressed in the window as a TV remote's. */
        fun deliver(key: Int) {
            if (app.lumiere.android.player.Theater.active && duringFilm(key)) return
            OpenApp.press?.invoke(key)
        }

        /**
         * During a film the room keeps the keys that would call up the window:
         * the stick's click opens the bar's More, B goes back through its menu
         * or Where to Watch first, and up or down only bring the bar. True when kept.
         */
        private fun duringFilm(key: Int): Boolean = when (key) {
            KeyEvent.KEYCODE_MENU -> { BarMenu.open("More"); FilmBar.wake(); true }
            KeyEvent.KEYCODE_BACK -> BarMenu.back() || PlacePicker.open.also { if (it) PlacePicker.open = false }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> { FilmBar.wake(); true }
            else -> false
        }

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
