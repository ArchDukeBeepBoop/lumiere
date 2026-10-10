package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.Discovery
import app.lumiere.android.api.FoundServer
import app.lumiere.android.api.Server
import app.lumiere.android.api.createFirstAccount
import app.lumiere.android.api.needsFirstAccount
import kotlinx.coroutines.launch

/**
 * Finding the server and signing in. Discovery runs on open, so on the home
 * network the server is usually already listed; the address field is the
 * fallback, prefilled with the last one used.
 */
@Composable
fun SignInScreen(state: AppState) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var found by remember { mutableStateOf<List<FoundServer>>(emptyList()) }
    var searching by remember { mutableStateOf(true) }
    var address by remember { mutableStateOf(state.lastServer ?: "http://") }
    var user by remember { mutableStateOf(state.lastUser ?: "") }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf("") }
    // A brand-new server answers that it has no account yet: make the first one.
    var needsAccount by remember { mutableStateOf(false) }
    LaunchedEffect(address) {
        kotlinx.coroutines.delay(500)
        needsAccount = runCatching { Server(normalise(address), state.deviceId).needsFirstAccount() }.getOrDefault(false)
    }

    LaunchedEffect(Unit) {
        found = Discovery.find(context)
        searching = false
        // The saved address, unless it no longer answers and the server was found elsewhere.
        val saved = state.lastServer
        val answers = saved != null && found.none { it.address.equals(normalise(saved), ignoreCase = true) } &&
            kotlinx.coroutines.withTimeoutOrNull(2_500) {
                runCatching { Server(normalise(saved), state.deviceId).publicInfo() }.isSuccess
            } == true
        app.lumiere.android.api.preferredAddress(saved?.let(::normalise), found, answers)?.let { address = it }
    }

    fun signIn() {
        scope.launch {
            busy = true
            message = null
            val url = normalise(address)
            val server = Server(url, state.deviceId)
            runCatching { if (needsAccount) server.createFirstAccount(user.trim(), password) else server.signIn(user.trim(), password) }
                .onSuccess { state.signedIn(it, server) }
                .onFailure {
                    message = it.message?.takeIf { m -> m.isNotBlank() && !m.startsWith("Failed to connect") }
                        ?: "Couldn't reach $url. Check that \"Share on my home network\" is on in Lumiere's " +
                        "Settings on the Mac, and that this device is on the same Wi-Fi."
                }
            busy = false
        }
    }

    Box(Modifier.fillMaxSize().background(Palette.canvas), contentAlignment = Alignment.Center) {
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Lumiere", style = MaterialTheme.typography.headlineLarge)
            Text(
                if (searching) "Looking for your server on this network…"
                else if (found.isEmpty()) "No server answered. Type its address — it is shown in Lumiere's " +
                    "Settings on the Mac, under Server Schedule."
                else "Found on this network:",
                style = MaterialTheme.typography.bodyMedium,
            )
            found.forEach { server ->
                LButton(primary = false, onClick = { address = server.address }, modifier = Modifier.fillMaxWidth()) {
                    Text("${server.name} — ${server.address}")
                }
            }
            OutlinedTextField(
                value = address, onValueChange = { address = it }, label = { Text("Server address") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            OutlinedTextField(
                value = user, onValueChange = { user = it }, label = { Text("User name") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password, onValueChange = { password = it }, label = { Text("Password") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )
            if (needsAccount) {
                OutlinedTextField(
                    value = confirm, onValueChange = { confirm = it }, label = { Text("Password again") },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("This server is new. Choose the name and password you'll use on every device.",
                    style = MaterialTheme.typography.bodyMedium)
            }
            message?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.background(Palette.surface, RoundedCornerShape(8.dp)).padding(12.dp))
            }
            Spacer(Modifier.height(4.dp))
            LButton(onClick = ::signIn,
                enabled = !busy && user.isNotBlank() && (!needsAccount || (password.length >= 4 && password == confirm)),
                modifier = Modifier.fillMaxWidth()) {
                Text(if (busy) "Signing in…" else if (needsAccount) "Create Account" else "Sign In")
            }
        }
    }
}

/** "192.168.60.5" → "http://192.168.60.5:8098": the scheme and port people leave off. */
fun normalise(raw: String): String {
    var url = raw.trim().trimEnd('/')
    if (!url.startsWith("http://") && !url.startsWith("https://")) url = "http://$url"
    val hostPart = url.substringAfter("://")
    if (!hostPart.contains(":")) url += ":8098"
    return url
}
