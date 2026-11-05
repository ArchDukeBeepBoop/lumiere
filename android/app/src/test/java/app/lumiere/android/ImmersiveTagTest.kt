package app.lumiere.android

import app.lumiere.android.ui.ImmersiveTag
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImmersiveTagTest {
    @Test fun readsTheTitlesOwnWords() {
        assertEquals("180°", ImmersiveTag.of("Alps VR180 4K"))
        assertEquals("360°", ImmersiveTag.of("Reef Dive (360)"))
        assertEquals("3D", ImmersiveTag.of("Avatar.2009.3D.HSBS"))
        assertEquals("3D", ImmersiveTag.of("Gravity [Half-SBS]"))
    }

    @Test fun ordinaryTitlesStayUntagged() {
        assertNull(ImmersiveTag.of("Absolution"))
        assertNull(ImmersiveTag.of("The Tobacco Years"))
    }
}
