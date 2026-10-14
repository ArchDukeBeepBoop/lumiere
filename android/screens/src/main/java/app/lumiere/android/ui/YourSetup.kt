package app.lumiere.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Prefs
import app.lumiere.android.Screen
import app.lumiere.android.api.changePassword
import kotlinx.coroutines.launch

/**
 * Settings › Your Setup, on the phone and the TV: the guide, the libraries and
 * the folders that fill them, every preference changed from how Lumiere
 * comes, and the account.
 */
@Composable
fun YourSetupSection(state: AppState) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Your Setup", style = MaterialTheme.typography.titleLarge, color = Palette.accent,
            modifier = Modifier.padding(top = 18.dp))
        LButton(primary = false, onClick = { state.push(Screen.Setup) }) { Text("Open the Setup Guide") }
        Text("Libraries & Folders", style = MaterialTheme.typography.titleMedium)
        LibrariesEditor(state)
        YourChanges(state)
        Account(state)
    }
}

/** Just the changed preferences, for the TV's own Settings layout. */
@Composable
fun YourChangesList(state: AppState) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { YourChanges(state, titled = false) }
}

@Composable
private fun YourChanges(state: AppState, titled: Boolean = true) {
    var tick by remember { mutableIntStateOf(0) }
    val changes = remember(tick) { state.settings.changes() }
    if (titled) Text("Your Changes", style = MaterialTheme.typography.titleMedium)
    if (changes.isEmpty()) {
        Text("Everything is as Lumiere comes.", style = MaterialTheme.typography.bodyMedium)
    }
    changes.forEach { (key, now, was) ->
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(Prefs.label(key), style = MaterialTheme.typography.bodyLarge)
                Text("$now · was $was", style = MaterialTheme.typography.labelMedium)
            }
            LButton(primary = false, onClick = { state.settings.reset(key); tick++ }) { Text("Reset") }
        }
    }
}

@Composable
private fun Account(state: AppState) {
    val scope = rememberCoroutineScope()
    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var note by remember { mutableStateOf<String?>(null) }
    Text("Account", style = MaterialTheme.typography.titleMedium)
    state.session?.let { Text("${it.userName} on ${it.serverName}", style = MaterialTheme.typography.bodyMedium) }
    OutlinedTextField(current, { current = it }, label = { Text("Current password") }, singleLine = true,
        visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    OutlinedTextField(new, { new = it }, label = { Text("New password") }, singleLine = true,
        visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
    LButton(enabled = current.isNotEmpty() && new.length >= 4, onClick = {
        scope.launch {
            note = runCatching { state.server!!.changePassword(current, new) }
                .fold({ current = ""; new = ""; "Changed." }, { "Not changed — check the current password." })
        }
    }) { Text("Change Password") }
    note?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
}
