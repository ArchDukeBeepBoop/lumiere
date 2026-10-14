package app.lumiere.android.ui

import app.lumiere.android.ui.Shortcuts.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The transport's pins: what a first run gets, how they're saved and read back, and the cap. */
class ShortcutsTest {
    @Test fun theIdsNeverChange() {
        // Saved on headsets: renaming one would quietly drop someone's pin.
        assertEquals(listOf("tracks", "smaller", "larger", "curve", "place", "menu", "sleep", "here", "speed", "sounds", "wall",
            "picture", "posture", "handmenu"),
            Action.entries.map { it.id })
    }

    @Test fun aFirstRunHasTheOldBarsButtons() {
        assertEquals(listOf(Action.TRACKS, Action.SMALLER, Action.LARGER, Action.PLACE), Shortcuts.decode(null))
    }

    @Test fun unpinningEverythingStaysEmpty() {
        assertEquals(emptyList<Action>(), Shortcuts.decode(""))
        assertEquals(emptyList<Action>(), Shortcuts.decode(Shortcuts.encode(emptyList())))
    }

    @Test fun theOrderSurvivesSaving() {
        val pins = listOf(Action.SPEED, Action.TRACKS, Action.SLEEP)
        assertEquals("speed,tracks,sleep", Shortcuts.encode(pins))
        assertEquals(pins, Shortcuts.decode(Shortcuts.encode(pins)))
    }

    @Test fun idsFromALaterVersionAndRepeatsArePassedOver() {
        assertEquals(listOf(Action.CURVE, Action.SPEED), Shortcuts.decode("curve,hologram,,speed,curve"))
    }

    @Test fun aSavedListNeverHoldsMoreThanTheBarDoes() {
        assertEquals(Shortcuts.MAX_PINNED, Shortcuts.decode(Action.entries.joinToString(",") { it.id }).size)
    }

    @Test fun pinningAddsAtTheEndAndUnpinningRemoves() {
        val pins = listOf(Action.TRACKS, Action.PLACE)
        assertEquals(listOf(Action.TRACKS, Action.PLACE, Action.SLEEP), Shortcuts.toggled(pins, Action.SLEEP))
        assertEquals(listOf(Action.PLACE), Shortcuts.toggled(pins, Action.TRACKS))
    }

    @Test fun aFullBarRefusesOneMoreButStillUnpins() {
        val full = Action.entries.take(Shortcuts.MAX_PINNED)
        assertNull(Shortcuts.toggled(full, Action.SPEED))
        assertEquals(full - Action.TRACKS, Shortcuts.toggled(full, Action.TRACKS))
    }

    @Test fun theSpeedStepsRoundAndComeBackToNormal() {
        val seen = generateSequence(1f) { Shortcuts.nextSpeed(it) }.take(5).toList()
        assertEquals(listOf(1f, 1.25f, 1.5f, 0.75f, 1f), seen)
        // A speed set elsewhere (the window's menu has 2×) steps back to normal.
        assertEquals(1f, Shortcuts.nextSpeed(2f))
    }

    @Test fun speedsReadAsOnARemote() {
        assertEquals(listOf("1×", "1.25×", "1.5×", "0.75×", "2×"), listOf(1f, 1.25f, 1.5f, 0.75f, 2f).map(Shortcuts::speedLabel))
    }

    @Test fun togglingKeepsTheCap() {
        Shortcuts.pinned.toList().forEach { Shortcuts.toggle(it) }
        val all = Action.entries.map { Shortcuts.toggle(it) }
        assertEquals(Shortcuts.MAX_PINNED, Shortcuts.pinned.size)
        assertEquals(List(Shortcuts.MAX_PINNED) { true } + List(Action.entries.size - Shortcuts.MAX_PINNED) { false }, all)
    }
}
