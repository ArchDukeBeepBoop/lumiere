package app.lumiere.android

import android.view.KeyEvent.*
import app.lumiere.android.player.TvRemote
import app.lumiere.android.player.TvRemote.Act
import app.lumiere.android.player.TvRemote.At
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The plan's remote table (TV_PLAYER_PLAN §5), row by row. */
class TvRemoteTest {
    private val clean = At(visible = false, zone = -1, scrubbing = false, buttons = 4)
    private val bar = clean.copy(visible = true)
    private val buttons = bar.copy(zone = 1)
    private val scrub = bar.copy(scrubbing = true)

    @Test fun okPausesFromCleanTogglesOnTheBarPressesAButtonCommitsAScrub() {
        assertEquals(Act.PauseAndShow, TvRemote.down(KEYCODE_DPAD_CENTER, 0, clean))
        assertEquals(Act.Toggle, TvRemote.down(KEYCODE_DPAD_CENTER, 0, bar))
        assertEquals(Act.Press(1), TvRemote.down(KEYCODE_DPAD_CENTER, 0, buttons))
        assertEquals(Act.Commit, TvRemote.down(KEYCODE_DPAD_CENTER, 0, scrub))
    }

    @Test fun leftAndRightMeanTimeUnlessOnTheButtons() {
        assertEquals(Act.Skip(10), TvRemote.down(KEYCODE_DPAD_RIGHT, 0, clean))
        assertEquals(Act.Skip(-10), TvRemote.down(KEYCODE_DPAD_LEFT, 0, clean))
        assertEquals(Act.Scrub(true), TvRemote.down(KEYCODE_DPAD_RIGHT, 3, clean))
        assertEquals(Act.Scrub(false), TvRemote.down(KEYCODE_DPAD_LEFT, 0, bar))
        assertEquals(Act.Zone(2), TvRemote.down(KEYCODE_DPAD_RIGHT, 0, buttons))
        assertEquals(Act.Zone(3), TvRemote.down(KEYCODE_DPAD_RIGHT, 0, buttons.copy(zone = 3)))
    }

    @Test fun upReachesTheButtonsDownTheTabs() {
        assertEquals(Act.Show, TvRemote.down(KEYCODE_DPAD_UP, 0, clean))
        assertEquals(Act.Zone(0), TvRemote.down(KEYCODE_DPAD_UP, 0, bar))
        assertEquals(Act.Zone(-1), TvRemote.down(KEYCODE_DPAD_DOWN, 0, buttons))
        assertEquals(Act.Tabs, TvRemote.down(KEYCODE_DPAD_DOWN, 0, bar))
        assertEquals(Act.Nothing, TvRemote.down(KEYCODE_DPAD_DOWN, 0, scrub))
    }

    @Test fun aStrayBackNeverEndsTheFilm() {
        assertEquals(Act.Show, TvRemote.back(clean))
        assertEquals(Act.Leave, TvRemote.back(bar))
        assertEquals(Act.Zone(-1), TvRemote.back(buttons))
        assertEquals(Act.Cancel, TvRemote.back(scrub))
    }

    @Test fun scrubbingGathersPaceAndOtherKeysAreNotThePlayers() {
        assertEquals(listOf(10f, 30f, 60f), listOf(0, 6, 14).map(TvRemote::step))
        assertEquals(Act.Commit, TvRemote.down(KEYCODE_MEDIA_PLAY_PAUSE, 0, scrub))
        assertEquals(Act.Skip(30), TvRemote.down(KEYCODE_MEDIA_FAST_FORWARD, 0, bar))
        assertNull(TvRemote.down(KEYCODE_VOLUME_UP, 0, bar))
    }
}
