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

private val tvPages = listOf(
    "Around Lumiere" to "Left opens the menu. Hold OK on any poster, or press Menu, for Mark Watched, My List, Go to Show and Download.",
    "While watching" to "Left and right skip — hold to go faster, with a preview. Down from the play button shows the season's episodes; down with the controls hidden opens audio and subtitles.",
    "The Menu button" to "During a film it opens speed, fit or fill, subtitle size and look, dialogue boost, night sound and the sleep timer. Back always closes what is open first.",
)

/** The same three cards for a Quest, whose remote is your hands: the ray, a pinch, the thumbstick, the Meta button. */
private val questPages = listOf(
    "Point and pinch" to "Point at anything and pinch, or pull the trigger, to choose it; pointing alone only looks. The thumbstick moves like a remote's arrows. Hold the Meta button to bring everything back in front of you.",
    "Your windows" to "Grab the bar under a window to carry it anywhere, and pull its corners to resize it. The tab bar beside it moves the same way, and the lock opens the Private Room.",
    "Watching" to "A film plays on its own screen in the place you choose: your room, a cinema, a cabin, the lakeside, the dark or space. The controls come to your hands; pinch the picture to bring them back, and pin the buttons you use most.",
)

private val pages get() = if (app.lumiere.android.AppBuild.quest) questPages else tvPages

/** Three cards on a TV's (or a Quest's) first open: the remote's grammar, once. Settings › TV & Projector can show it again. */
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
