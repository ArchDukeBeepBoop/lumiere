package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** "Leave Lumiere?" — Stay has focus, so a Back pressed once too often costs nothing. */
@Composable
fun ExitDialog(onStay: () -> Unit, onLeave: () -> Unit) {
    val stay = remember { FocusRequester() }
    androidx.activity.compose.BackHandler(onBack = onStay)
    LaunchedEffect(Unit) { runCatching { stay.requestFocus() } }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
        Column(Modifier.holdsRemote().frosted(22).padding(horizontal = 26.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Leave Lumiere?", style = MaterialTheme.typography.titleLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                LButton(onClick = onStay, modifier = Modifier.focusRequester(stay)) { Text("Stay") }
                LButton(primary = false, onClick = onLeave) { Text("Leave") }
            }
        }
    }
}
