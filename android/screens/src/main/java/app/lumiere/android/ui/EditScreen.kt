package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.api.editItem
import app.lumiere.android.api.lyrics
import app.lumiere.android.api.saveLyrics
import app.lumiere.android.api.toLrc
import kotlinx.coroutines.launch

/**
 * Editing a title's details — the Mac's Edit Metadata — and a track's lyrics,
 * which keep their timing when they are synced.
 */
@Composable
fun EditScreen(state: AppState, id: String) {
    val server = state.server ?: return
    val userId = state.session?.userId ?: return
    val form = LocalFormFactor.current
    val scope = rememberCoroutineScope()
    var loaded by remember { mutableStateOf(false) }
    var isAudio by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var sortName by remember { mutableStateOf("") }
    var year by remember { mutableStateOf("") }
    var genres by remember { mutableStateOf("") }
    var overview by remember { mutableStateOf("") }
    var lyrics by remember { mutableStateOf("") }
    var originalLyrics by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(id) {
        runCatching { server.item(userId, id) }.onSuccess { item ->
            name = item.name; year = item.year?.toString() ?: ""; overview = item.overview ?: ""
            genres = item.genres.joinToString(", "); isAudio = item.isAudio
            if (isAudio) server.lyrics(id)?.let { lyrics = toLrc(it); originalLyrics = lyrics }
            loaded = true
        }.onFailure { message = it.message }
    }

    LazyColumn(Modifier.fillMaxSize().background(Palette.canvas),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(form.gutter.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Text("Edit", style = MaterialTheme.typography.headlineLarge) }
        if (loaded) {
            item { Field("Title", name) { name = it } }
            item { Field("Sort title (blank to follow the title)", sortName) { sortName = it } }
            item { Field("Year", year) { year = it.filter(Char::isDigit).take(4) } }
            item { Field("Genres, separated by commas", genres) { genres = it } }
            item { Field("Overview", overview, lines = 5) { overview = it } }
            if (isAudio) item { Field("Lyrics (LRC lines keep their timing)", lyrics, lines = 8) { lyrics = it } }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    LButton(onClick = {
                        scope.launch {
                            runCatching {
                                server.editItem(userId, id, buildMap {
                                    put("Name", name.trim())
                                    if (sortName.isNotBlank()) put("ForcedSortName", sortName.trim())
                                    put("ProductionYear", year.toIntOrNull())
                                    put("Overview", overview.trim().ifEmpty { null })
                                    put("Genres", org.json.JSONArray(genres.split(',').map { it.trim() }.filter { it.isNotEmpty() }))
                                })
                                if (isAudio && lyrics != originalLyrics && lyrics.isNotBlank()) server.saveLyrics(id, lyrics)
                            }.onSuccess { state.pop() }.onFailure { message = "Not saved: ${it.message}" }
                        }
                    }) { Text("Save") }
                    LButton(primary = false, onClick = { state.pop() }) { Text("Cancel") }
                }
            }
        }
        message?.let { item { Text(it, color = Palette.accent) } }
    }
}

@Composable
private fun Field(label: String, value: String, lines: Int = 1, set: (String) -> Unit) {
    OutlinedTextField(value, set, label = { Text(label) }, singleLine = lines == 1, minLines = lines,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp))
}
