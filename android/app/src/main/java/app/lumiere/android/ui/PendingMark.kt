package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.lumiere.android.cache.WatchLedger

/**
 * A small cloud on a title whose watched mark or place was made here and has
 * not yet reached the Mac — the way Photos marks a picture still uploading.
 * It goes once the ledger is flushed. See `WatchLedger`.
 */
@Composable
fun PendingMark(id: String, modifier: Modifier = Modifier) {
    val ledger = LocalLedger.current ?: return
    @Suppress("UNUSED_VARIABLE") val version = ledger.version.intValue
    if (ledger.get(id)?.pending != true) return
    Icon(Icons.Filled.CloudUpload, contentDescription = "Waiting to reach the Mac", tint = Color.White,
        modifier = modifier.background(Color.Black.copy(alpha = 0.55f), CircleShape).padding(4.dp).size(14.dp))
}

/** The device's [WatchLedger], for cards that are not handed the app state. */
val LocalLedger = androidx.compose.runtime.staticCompositionLocalOf<WatchLedger?> { null }
