package app.lumiere.android.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SubtitlePickTest {
    private data class T(val label: String, val lang: String?)
    private val signs = T("Signs & Songs / KawaSubs", "en")
    private val full = T("Full Subtitles / KawaSubs", "en")
    private val french = T("Français", "fr")

    @Test fun theFullTrackIsMeantOverSignsAndSongs() {
        assertEquals(full, SubtitlePick.full(listOf(signs, full), { it.label }))
        assertEquals(full, SubtitlePick.better(listOf(signs, full, french), signs, { it.label }, { it.lang }))
    }

    @Test fun aFullTrackChosenIsLeftAlone() {
        assertNull(SubtitlePick.better(listOf(signs, full), full, { it.label }, { it.lang }))
    }

    @Test fun signsAloneStay() {
        // No full track in its language: the signs track is what there is.
        assertNull(SubtitlePick.better(listOf(signs, french), signs, { it.label }, { it.lang }))
        assertEquals(signs, SubtitlePick.full(listOf(signs), { it.label }))
    }
}
