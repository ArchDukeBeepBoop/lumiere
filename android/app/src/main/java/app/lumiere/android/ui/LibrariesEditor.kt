package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.FolderEntry
import app.lumiere.android.api.LibraryKind
import app.lumiere.android.api.ServerLibrary
import app.lumiere.android.api.addLibraryFolder
import app.lumiere.android.api.browse
import app.lumiere.android.api.createLibrary
import app.lumiere.android.api.libraries
import app.lumiere.android.api.removeLibrary
import app.lumiere.android.api.removeLibraryFolder
import app.lumiere.android.api.setPrivateLibraries
import kotlinx.coroutines.launch

/**
 * The server's libraries and the folders that fill them, as on the Mac: the
 * setup guide and Settings › Your Setup both draw this, so what one sets the
 * other shows. Folders are chosen by browsing the server's own disk.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LibrariesEditor(state: AppState, showsRoom: Boolean = true) {
    val server = state.server ?: return
    val scope = rememberCoroutineScope()
    var libraries by remember { mutableStateOf<List<ServerLibrary>>(emptyList()) }
    var reload by remember { mutableIntStateOf(0) }
    var adding by remember { mutableStateOf(false) }
    var pickingFor by remember { mutableStateOf<ServerLibrary?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(reload) { libraries = runCatching { server.libraries() }.getOrDefault(libraries) }

    fun act(change: suspend () -> Unit) {
        scope.launch {
            message = runCatching { change() }.exceptionOrNull()?.message
            reload++
            state.followLibrary()
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (libraries.isEmpty() && !adding) {
            Text("No libraries yet. Add one and choose the folders that hold your films, shows or music — nothing in them is moved or changed.",
                style = MaterialTheme.typography.bodyMedium)
        }
        libraries.forEach { library ->
            Column(Modifier.fillMaxWidth().background(Palette.surface, RoundedCornerShape(12.dp)).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(library.name, style = MaterialTheme.typography.titleMedium)
                Text("${LibraryKind.of(library.kind).title} · ${library.items} items", style = MaterialTheme.typography.labelMedium)
                library.folders.forEach { folder ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(folder.path, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        LButton(primary = false, onClick = { act { server.removeLibraryFolder(library.id, folder.id) } }) { Text("Remove") }
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    LButton(primary = false, onClick = { pickingFor = library }) { Text("Add Folder") }
                    LButton(primary = false, onClick = { act { server.removeLibrary(library.id) } }) { Text("Remove Library") }
                }
                if (showsRoom) {
                    val private = library.id in state.privateLibraries
                    Row(Modifier.fillMaxWidth().focusCard {
                        act { setPrivate(state, library.id, !private) }
                    }, verticalAlignment = Alignment.CenterVertically) {
                        Text("In the Private Room", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        Switch(private, { on -> act { setPrivate(state, library.id, on) } })
                    }
                }
                if (pickingFor?.id == library.id) {
                    FolderPicker(state, onPick = { path -> pickingFor = null; act { server.addLibraryFolder(library.id, path) } },
                        onCancel = { pickingFor = null })
                }
            }
        }
        if (adding) {
            AddLibrary(state, onDone = { adding = false; reload++; state.followLibrary() })
        } else {
            LButton(onClick = { adding = true }) { Text("Add Library") }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }
}

/** Moves a library into or out of the Private Room, on the server for every device. */
suspend fun setPrivate(state: AppState, id: String, on: Boolean) {
    val ids = state.privateLibraries.toMutableSet().apply { if (on) add(id) else remove(id) }
    state.server?.setPrivateLibraries(ids)
    if (state.settings.privateFollowsMac) state.macPrivate = ids else state.settings.privateLibraries = ids
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AddLibrary(state: AppState, onDone: () -> Unit) {
    val server = state.server ?: return
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf(LibraryKind.Movies) }
    var paths by remember { mutableStateOf<List<String>>(emptyList()) }
    var picking by remember { mutableStateOf(true) }
    var message by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxWidth().background(Palette.surface, RoundedCornerShape(12.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("New library", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            LibraryKind.entries.forEach { k -> LChip(kind == k, { kind = k }, { Text(k.title) }) }
        }
        Text(kind.note, style = MaterialTheme.typography.labelMedium)
        paths.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
        if (picking) {
            FolderPicker(state, onPick = { path ->
                if (path !in paths) paths = paths + path
                if (name.isBlank()) name = path.substringAfterLast('/')
                picking = false
            }, onCancel = { picking = false })
        } else {
            LButton(primary = false, onClick = { picking = true }) { Text(if (paths.isEmpty()) "Choose a Folder" else "Add Another Folder") }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LButton(primary = false, onClick = onDone) { Text("Cancel") }
            LButton(enabled = paths.isNotEmpty(), onClick = {
                scope.launch {
                    runCatching { server.createLibrary(name.ifBlank { kind.title }, kind, paths) }
                        .onSuccess { onDone() }.onFailure { message = it.message }
                }
            }) { Text("Add Library") }
        }
    }
}

/** Walks the server's disk a folder at a time; "Use This Folder" picks the one open. */
@Composable
fun FolderPicker(state: AppState, onPick: (String) -> Unit, onCancel: () -> Unit) {
    val server = state.server ?: return
    var path by remember { mutableStateOf<String?>(null) }
    var parent by remember { mutableStateOf<String?>(null) }
    var folders by remember { mutableStateOf<List<FolderEntry>>(emptyList()) }
    LaunchedEffect(path) {
        runCatching { server.browse(path) }.onSuccess { (up, list) -> parent = up; folders = list }
    }
    Column(Modifier.fillMaxWidth().background(Palette.canvas, RoundedCornerShape(10.dp)).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(path ?: "Choose a folder on the server", style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            path?.let { open -> LButton(onClick = { onPick(open) }) { Text("Use This Folder") } }
            if (path != null) LButton(primary = false, onClick = { path = parent }) { Text("Up") }
            LButton(primary = false, onClick = onCancel) { Text("Cancel") }
        }
        folders.forEach { entry ->
            Text("📁  ${entry.name}", style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.fillMaxWidth().focusCard { path = entry.path }.padding(vertical = 8.dp, horizontal = 6.dp))
        }
        if (folders.isEmpty()) Text("No folders inside.", style = MaterialTheme.typography.bodySmall)
    }
}
