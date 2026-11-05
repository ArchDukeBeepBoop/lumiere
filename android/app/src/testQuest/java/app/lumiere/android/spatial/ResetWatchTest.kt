package app.lumiere.android.spatial

import com.meta.spatial.core.Vector3
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ResetWatchTest {
    private val ahead = Vector3(0f, 0f, 1f)

    @Test fun aHeadTurnOrAStepIsNotAReset() {
        val turned = Vector3(kotlin.math.sin(0.3f), 0f, kotlin.math.cos(0.3f))   // 17°
        assertFalse(ResetWatch.isReset(Vector3(0f), ahead, Vector3(0.05f, 0f, 0f), turned))
    }

    @Test fun aSuddenTurnOrJumpIsAReset() {
        assertTrue(ResetWatch.isReset(Vector3(0f), ahead, Vector3(0f), Vector3(1f, 0f, 0f)))
        assertTrue(ResetWatch.isReset(Vector3(0f), ahead, Vector3(0.8f, 0f, 0f), ahead))
    }
}
