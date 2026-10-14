package app.lumiere.android.local

import android.graphics.Bitmap
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * On this headset: the videos kept on the device, newest first, each a
 * picture from it, its name, length and folder; a press plays it in the
 * player and the Theater as the server's films play. Asks once to see them.
 */
@Composable
fun OnDeviceScreen(state: AppState) {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(LocalVideos.allowed(context)) }
    var refresh by remember { mutableIntStateOf(0) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed = it; refresh++ }
    LaunchedEffect(Unit) { if (!allowed) ask.launch(LocalVideos.PERMISSION) }
    val videos by produceState<List<LocalVideos.Video>?>(null, allowed, refresh) {
        value = if (!allowed) emptyList() else withContext(Dispatchers.IO) { LocalVideos.list(context) }
    }
    Column(Modifier.fillMaxSize().background(Palette.canvas).padding(horizontal = 48.dp, vertical = 28.dp)) {
        Text("On this headset", style = MaterialTheme.typography.headlineSmall)
        Text("Videos kept on the device: Movies, Download and any folder you've copied them to.",
            style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 18.dp))
        val list = videos
        when {
            !allowed -> Text("Lumiere needs permission to see your videos. Choose On this headset again to be asked, or allow it in Settings › Apps › Lumiere.",
                color = Palette.textSecondary)
            list == null -> Text("Looking…", color = Palette.textSecondary)
            list.isEmpty() -> Text("No videos on this headset yet. Copy some into its Movies or Download folder (with SideQuest, or a USB cable) and come back.",
                color = Palette.textSecondary)
            else -> LazyVerticalGrid(GridCells.Adaptive(260.dp), horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp), contentPadding = PaddingValues(bottom = 40.dp)) {
                items(list, key = { it.uri.toString() }) { v -> VideoCard(v) { state.push(Screen.Player(LocalVideos.idOf(v), 0.0)) } }
            }
        }
    }
}

@Composable
private fun VideoCard(v: LocalVideos.Video, onClick: () -> Unit) {
    val context = LocalContext.current
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val thumb by produceState<Bitmap?>(null, v.uri) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                if (android.os.Build.VERSION.SDK_INT >= 29) context.contentResolver.loadThumbnail(v.uri, Size(480, 270), null) else null
            }.getOrNull()
        }
    }
    Column(Modifier.clip(RoundedCornerShape(12.dp)).hoverable(source).clickable(interactionSource = source, indication = null, onClick = onClick)) {
        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(12.dp)).background(Palette.surfaceRaised)
            .border(if (hovered) 3.dp else 0.dp, if (hovered) Palette.accent else Color.Transparent, RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center) {
            thumb?.let { Image(it.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
                ?: Text("▶", color = Palette.textSecondary, style = MaterialTheme.typography.headlineMedium)
        }
        Text(v.name.substringBeforeLast('.'), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 8.dp))
        val minutes = v.durationMs / 60_000
        Text(listOfNotNull(if (minutes > 0) "$minutes min" else null, v.folder.takeIf { it.isNotBlank() },
            if (v.height > 0) "${v.height}p" else null).joinToString(" · "),
            style = MaterialTheme.typography.labelMedium, color = Palette.textSecondary, maxLines = 1)
    }
}
