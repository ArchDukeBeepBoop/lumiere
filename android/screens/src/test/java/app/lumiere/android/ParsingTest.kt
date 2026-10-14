package app.lumiere.android

import app.lumiere.android.api.parseItems
import app.lumiere.android.api.parseSegments
import app.lumiere.android.ui.normalise
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsingTest {
    @Test fun episodeFromTheServerShape() {
        val body = """{"Items":[{"Id":"abc","Name":"Patience of Iron","Type":"Episode","SeriesName":"Angels of Death",
            "SeriesId":"s1","IndexNumber":1,"ParentIndexNumber":1,"RunTimeTicks":14632739999,
            "UserData":{"PlaybackPositionTicks":7316369999,"Played":false},
            "ImageTags":{"Primary":"t1"},"MediaSources":[{"Id":"abc","MediaStreams":[
              {"Index":2,"Type":"Subtitle","Language":"eng","IsExternal":true,"Codec":"subrip"}]}]}]}"""
        val item = parseItems(body).single()
        assertEquals("S1 · E1", item.episodeLabel)
        assertEquals(0.5f, item.progress!!, 0.01f)
        assertEquals("abc", item.mediaSourceId)
        assertTrue(item.streams.single().isExternal)
    }

    @Test fun latestIsABareArray() {
        assertEquals(2, parseItems("""[{"Id":"a","Name":"A","Type":"Movie"},{"Id":"b","Name":"B","Type":"Series"}]""").size)
    }

    @Test fun unstartedHasNoProgress() {
        assertNull(parseItems("""[{"Id":"a","Name":"A","Type":"Movie","RunTimeTicks":100}]""").single().progress)
    }

    @Test fun segmentsInSeconds() {
        val s = parseSegments("""{"Items":[{"Type":"Intro","StartTicks":0,"EndTicks":900000000}]}""").single()
        assertEquals(90.0, s.endSeconds, 0.0)
    }

    @Test fun addressesGetTheirSchemeAndPort() {
        assertEquals("http://192.168.60.5:8098", normalise("192.168.60.5"))
        assertEquals("http://mac.local:9000", normalise("http://mac.local:9000/"))
    }
}
