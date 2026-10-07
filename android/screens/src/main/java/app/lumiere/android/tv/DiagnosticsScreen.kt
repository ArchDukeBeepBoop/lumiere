package app.lumiere.android.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Diagnostics
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.focusCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What Send Diagnostics would send, readable on the device itself. Up and down scroll it. */
@Composable
fun DiagnosticsScreen(state: AppState) {
    var lines by remember { mutableStateOf(listOf("Reading…")) }
    LaunchedEffect(Unit) { lines = withContext(Dispatchers.IO) { Diagnostics.report().lines() } }
    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas).padding(32.dp)) {
        item { Text("Diagnostics", style = MaterialTheme.typography.headlineLarge) }
        items(lines) { l ->
            Text(l, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Palette.textSecondary,
                modifier = Modifier.focusCard {}.padding(vertical = 2.dp))
        }
    }
}
