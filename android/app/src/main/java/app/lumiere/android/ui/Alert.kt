package app.lumiere.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** One button of an alert: its label, whether it destroys something, and what it does. */
class AlertButton(val label: String, val destructive: Boolean = false, val onClick: () -> Unit)

/**
 * tvOS's alert: a title and a line of explanation centred on a frosted card,
 * the choices stacked full width beneath, the safe one focused so a stray press
 * costs nothing, a destructive one in red.
 */
@Composable
fun TvAlertCard(title: String, message: String?, buttons: List<AlertButton>, focused: Int = buttons.lastIndex) {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    Column(Modifier.holdsRemote().width(460.dp).frosted(22).padding(horizontal = 24.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold), textAlign = TextAlign.Center)
        message?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary, textAlign = TextAlign.Center) }
        Box(Modifier.padding(top = 8.dp))
        buttons.forEachIndexed { i, b ->
            TvPill(b.onClick, Modifier.fillMaxWidth().then(if (i == focused) Modifier.focusRequester(first) else Modifier),
                selected = true, tint = if (b.destructive) Color(0xFFFF6961) else Palette.textPrimary, shape = RoundedCornerShape(14.dp)) {
                Text(b.label, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            }
        }
    }
}
