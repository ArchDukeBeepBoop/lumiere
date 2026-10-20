package app.lumiere.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/**
 * tvOS's notification: a frosted capsule sliding in at the top right — a round
 * symbol, a line, a quieter line — and gone after a few seconds. Never takes
 * the remote. Anything may post one, from any thread.
 */
object Notice {
    class Shown(val title: String, val detail: String?, val icon: ImageVector?, val tint: Color)
    var current by mutableStateOf<Shown?>(null)
        private set
    private var count = 0

    fun show(title: String, detail: String? = null, icon: ImageVector? = null, tint: Color = Color(0xFF34C759)) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { current = Shown(title, detail, icon, tint); count++ }
    }

    @Composable
    fun Host() {
        var last by remember { mutableStateOf<Shown?>(null) }
        current?.let { last = it }
        LaunchedEffect(current) { if (current != null) { kotlinx.coroutines.delay(3_500); current = null } }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopEnd) {
            AnimatedVisibility(current != null, enter = slideInHorizontally { it } + fadeIn(), exit = slideOutHorizontally { it } + fadeOut()) {
                last?.let { n ->
                    Row(Modifier.padding(top = 28.dp, end = 32.dp).frosted(30).padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        n.icon?.let { Box(Modifier.size(36.dp).background(n.tint, CircleShape), contentAlignment = Alignment.Center) {
                            Icon(it, null, tint = Color.White, modifier = Modifier.size(20.dp)) } }
                        Column {
                            Text(n.title, style = MaterialTheme.typography.titleSmall, color = Palette.textPrimary)
                            n.detail?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = Palette.textSecondary) }
                        }
                    }
                }
            }
        }
    }
}
