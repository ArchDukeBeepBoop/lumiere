package app.lumiere.android.player

import android.view.KeyEvent

/**
 * The TV player's remote as a table (TV_PLAYER_PLAN §5): given where the player
 * is and which key went down, what should happen. Pure, so every row of the
 * plan's table is tested without a screen; [PlayerOverlay] carries the act out.
 */
internal object TvRemote {
    /** Where the player is: transport showing, which zone has the remote, scrubbing or not. */
    data class At(val visible: Boolean, val zone: Int, val scrubbing: Boolean, val buttons: Int)

    sealed interface Act {
        data object Show : Act
        data object PauseAndShow : Act
        data object Toggle : Act
        data object ToggleAndShow : Act
        data class Press(val button: Int) : Act
        data object Commit : Act
        data object Cancel : Act
        data class Scrub(val forward: Boolean) : Act
        data class Skip(val seconds: Int) : Act
        data class Zone(val zone: Int) : Act
        data object Leave : Act
        data object Tabs : Act
        data object Menu : Act
        data object Nothing : Act
    }

    /** Scrubbing gathers pace while a key is held: 10 s a step, then 30, then 60. */
    fun step(repeat: Int): Float = when { repeat < 6 -> 10f; repeat < 14 -> 30f; else -> 60f }

    /** A short Back, decided on its release. */
    fun back(at: At): Act = when {
        at.scrubbing -> Act.Cancel
        at.zone >= 0 -> Act.Zone(-1)
        // A stray Back never ends the film: with nothing showing, it shows the transport.
        !at.visible -> Act.Show
        else -> Act.Leave
    }

    /** A key going down. Null: not the player's key. */
    fun down(code: Int, repeat: Int, at: At): Act? = when (code) {
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> when {
            repeat > 0 -> Act.Nothing
            at.scrubbing -> Act.Commit
            !at.visible -> Act.PauseAndShow
            at.zone >= 0 -> Act.Press(at.zone)
            else -> Act.Toggle
        }
        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> when {
            repeat > 0 -> Act.Nothing
            at.scrubbing -> Act.Commit
            else -> Act.ToggleAndShow
        }
        KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
            val forward = code == KeyEvent.KEYCODE_DPAD_RIGHT
            when {
                at.zone >= 0 -> Act.Zone((at.zone + if (forward) 1 else -1).coerceIn(0, (at.buttons - 1).coerceAtLeast(0)))
                at.scrubbing || at.visible || repeat > 0 -> Act.Scrub(forward)
                // A tap with nothing showing: ten seconds, marked beside the playhead.
                else -> Act.Skip(if (forward) 10 else -10)
            }
        }
        KeyEvent.KEYCODE_DPAD_UP -> when {
            at.scrubbing -> Act.Nothing
            !at.visible -> Act.Show
            at.zone < 0 -> Act.Zone(0)
            else -> Act.Nothing
        }
        KeyEvent.KEYCODE_DPAD_DOWN -> when {
            at.scrubbing -> Act.Nothing
            !at.visible -> Act.Show
            at.zone >= 0 -> Act.Zone(-1)
            else -> Act.Tabs
        }
        KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_SETTINGS -> Act.Menu
        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> Act.Skip(30)
        KeyEvent.KEYCODE_MEDIA_REWIND -> Act.Skip(-30)
        else -> null
    }
}
