package app.lumiere.android.tv

import app.lumiere.android.ui.holdsRemote
import app.lumiere.android.ui.frosted

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.ui.LButton
import app.lumiere.android.ui.Palette

private val pages = listOf(
    "Around Lumiere" to "Left opens the menu. Hold OK on any poster, or press Menu, for Mark Watched, Favourite, Go to Show and Download.",
    "While watching" to "Left and right skip — hold to go faster, with a preview. Down from the play button shows the season's episodes; down with the controls hidden opens audio and subtitles.",
    "The Menu button" to "During a film it opens speed, fit or fill, subtitle size and look, dialogue boost, night sound and the sleep timer. Back always closes what is open first.",
)

/** Three cards on a TV's first open: the remote's grammar, once. Settings › TV & Projector can show it again. */
@Composable
fun TvTour(state: AppState) {
    if (state.settings.tvTourShown) return
    var page by remember { mutableIntStateOf(0) }
    val next = remember { FocusRequester() }
    LaunchedEffect(page) { runCatching { next.requestFocus() } }
    androidx.activity.compose.BackHandler { state.settings.tvTourShown = true }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.82f)), contentAlignment = Alignment.Center) {
        Column(Modifier.holdsRemote().widthIn(max = 640.dp).frosted(18).padding(32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("${page + 1} of ${pages.size}", style = MaterialTheme.typography.labelMedium, color = Palette.accent)
            Text(pages[page].first, style = MaterialTheme.typography.headlineLarge)
            Text(pages[page].second, style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LButton(modifier = Modifier.focusRequester(next), onClick = {
                    if (page < pages.lastIndex) page++ else state.settings.tvTourShown = true
                }) { Text(if (page < pages.lastIndex) "Next" else "Start Watching") }
                if (page < pages.lastIndex) LButton(primary = false, onClick = { state.settings.tvTourShown = true }) { Text("Skip") }
            }
        }
    }
}
