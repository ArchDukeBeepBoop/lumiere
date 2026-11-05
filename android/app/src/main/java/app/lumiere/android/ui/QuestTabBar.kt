package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ViewInAr
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.QuestPlaces
import app.lumiere.android.Screen

/**
 * The Quest window's navigation: a glass capsule floating at the top of the page, as
 * Meta's TV app and visionOS keep theirs, so the window is all picture. The
 * main places sit in it; ⋯ opens the rest above it (Watchlist, Music, the
 * library's other shelves, the Private Room, Settings, where films play).
 */
@Composable
fun QuestTabBar(state: AppState, top: Screen, modifier: Modifier) {
    val views = state.visibleViews(state.views)
    fun lib(match: (app.lumiere.android.api.Item) -> Boolean) = views.firstOrNull(match)
    val music = lib { it.collectionType == "music" }
    val immersive = lib { v -> listOf("3d", "vr", "immersive", "180", "360").any { v.name.lowercase().split(' ', '-', '_').contains(it) } }
    val root = state.stack.getOrNull(1) ?: Screen.Home
    val activity = LocalContext.current as? android.app.Activity
    val main = listOfNotNull(
        Row("Home", Icons.Default.Home, root == Screen.Home) { state.tab(Screen.Home) },
        // Library holds every library; a tab per library named what it isn't misled.
        Row("Library", Icons.Default.VideoLibrary, root == Screen.TvLibrary || root is Screen.Library) { state.tab(Screen.TvLibrary) },
        music?.let { v -> Row("Music", Icons.Default.LibraryMusic, root is Screen.Music) { state.tab(Screen.Music(v)) } },
        Row("Search", Icons.Default.Search, root == Screen.Search) { state.tab(Screen.Search) },
    )
    // Everything else the TV keeps in its Library and menu bar, so nothing is out of reach.
    val more = listOfNotNull(
        Row("Watchlist", Icons.Default.Star, root == Screen.Favourites) { state.tab(Screen.Favourites) },
        immersive?.let { v -> Row("Immersive", Icons.Default.ViewInAr, (root as? Screen.Library)?.view?.id == v.id) { state.tab(Screen.Library(v)) } },
        Row("Collections", Icons.Default.Collections, root == Screen.Collections) { state.tab(Screen.Collections) },
        Row("Playlists", Icons.Default.PlaylistPlay, root is Screen.Playlist || root == Screen.Playlists) { state.tab(Screen.Playlists) },
        Row("Downloaded", Icons.Default.Download, root == Screen.Downloads) { state.tab(Screen.Downloads) },
        Row("On This Device", Icons.Default.Folder, root == Screen.OnThisPhone) { state.tab(Screen.OnThisPhone) },
        if (app.lumiere.android.music.Music.current != null) Row("Now Playing", Icons.Default.GraphicEq, root == Screen.NowPlaying) { state.push(Screen.NowPlaying) } else null,
        if (state.privateLibraries.isEmpty() || activity == null) null
        else Row(if (state.roomOpen) "Leave Private Room" else "Private Room", if (state.roomOpen) Icons.Default.LockOpen else Icons.Default.Lock, state.roomOpen) {
            state.tab(Screen.Home); toggleRoom(state, activity)
        },
        Row("Settings", Icons.Default.Settings, root == Screen.Settings) { state.guarded { state.tab(Screen.Settings) } },
    )
    // A section's page, as opened from here, glows in the section's colour; a title's page in the title's.
    val section = if (top == root) (main + more).firstOrNull { it.on }?.label else null
    androidx.compose.runtime.LaunchedEffect(section) { QuestGround.section = QuestGround.sectionColour(section) }
    var open by remember { androidx.compose.runtime.mutableStateOf(false) }
    androidx.compose.foundation.layout.Box(modifier.padding(top = 14.dp, bottom = 6.dp)) {
        // Floating: lifted off the page by its shadow, the glow showing through the glass.
        Row(Modifier.graphicsLayer { shadowElevation = 40f; shape = RoundedCornerShape(50); clip = true }
            .background(Palette.chrome.copy(alpha = 0.72f))
            .drawBehind { drawRoundRect(Color.White.copy(alpha = 0.10f), style = androidx.compose.ui.graphics.drawscope.Stroke(1.5f),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2)) }
            .padding(6.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            // Music has no screen of its own while you browse: what is playing rides in the bar.
            if (app.lumiere.android.music.Music.current != null) { NowPlayingPill(state); Spacer(Modifier.width(6.dp)) }
            // A narrow window, or one sharing the bar with a song, keeps the tabs to their icons.
            val roomy = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >=
                if (app.lumiere.android.music.Music.current != null) 1180 else 900
            main.forEach { r -> TabPill(r, label = roomy) }
            // The rest rises from ⋯ itself, solid so the page behind never shows through the words.
            androidx.compose.foundation.layout.Box {
                TabPill(Row("More", Icons.Default.MoreHoriz, open || more.any { it.on }) { open = !open }, label = false)
                // The rest, in a glass panel rising above the capsule.
                androidx.compose.material3.DropdownMenu(open, { open = false }, containerColor = Palette.chrome,
                    shape = RoundedCornerShape(24.dp)) {
                    Column(Modifier.width(280.dp).padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        more.forEach { r -> RailRow(r.copy(go = { open = false; r.go() }), true) }
                        Spacer(Modifier.height(6.dp))
                        WhereToWatch(true)
                    }
                }
            }
        }
    }
}

/** One place in the capsule: its icon and name, lit when you are there, lifted when pointed at. */
@Composable
private fun TabPill(r: Row, label: Boolean = true) {
    val hover = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val over by hover.collectIsHoveredAsState()
    val lift by androidx.compose.animation.core.animateFloatAsState(if (over) 1.06f else 1f, label = "tabLift")
    Row(Modifier.height(52.dp).graphicsLayer { scaleX = lift; scaleY = lift }.clip(RoundedCornerShape(50))
        .background(when { r.on -> Color.White.copy(alpha = 0.16f); over -> Color.White.copy(alpha = 0.08f); else -> Color.Transparent })
        .hoverable(hover).clickable(onClickLabel = r.label, onClick = r.go).padding(horizontal = if (label) 18.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(r.icon, r.label, Modifier.size(22.dp), tint = if (r.on) Palette.textPrimary else Palette.textSecondary)
        if (label) Text(r.label, maxLines = 1, style = TextStyle(fontSize = 16.sp,
            fontWeight = if (r.on) FontWeight.SemiBold else FontWeight.Medium, color = if (r.on) Palette.textPrimary else Palette.textSecondary))
    }
}

private data class Row(val label: String, val icon: ImageVector, val on: Boolean, val go: () -> Unit)

@Composable
private fun RailRow(r: Row, wide: Boolean) {
    // At least 48 dp to aim at, as Horizon OS asks; pointed at, a row lifts and brightens, as the cards do.
    val hover = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val over by hover.collectIsHoveredAsState()
    val lift by androidx.compose.animation.core.animateFloatAsState(if (over) 1.04f else 1f, label = "railLift")
    Row(Modifier.fillMaxWidth().height(48.dp).graphicsLayer { scaleX = lift; scaleY = lift }.clip(RoundedCornerShape(14.dp))
        .background(when { r.on -> Palette.surfaceRaised; over -> Color.White.copy(alpha = 0.10f); else -> Color.Transparent })
        .hoverable(hover)
        .clickable(onClickLabel = r.label, onClick = r.go).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(r.icon, r.label, Modifier.size(24.dp), tint = if (r.on) Palette.accent else Palette.textSecondary)
        if (wide) Text(r.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = TextStyle(fontSize = 17.sp, fontWeight = if (r.on) FontWeight.SemiBold else FontWeight.Medium,
                color = if (r.on) Palette.textPrimary else Palette.textSecondary))
    }
}

/** The place round you when a film plays: its name; a pinch lists them all to choose from. */
@Composable
private fun WhereToWatch(wide: Boolean) {
    val context = LocalContext.current
    var chosen by remember(app.lumiere.android.QuestPlaces.chosen(context)) { mutableIntStateOf(QuestPlaces.chosen(context)) }
    var open by remember { androidx.compose.runtime.mutableStateOf(false) }
    val label = QuestPlaces.all[chosen].second
    androidx.compose.foundation.layout.Box {
        androidx.compose.material3.DropdownMenu(open, { open = false }, containerColor = Palette.surfaceRaised) {
            QuestPlaces.all.forEachIndexed { i, (_, name) ->
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text((if (i == chosen) "✓  " else "     ") + name, style = TextStyle(fontSize = 16.sp, color = Palette.textPrimary)) },
                    onClick = { chosen = i; QuestPlaces.choose(context, i); open = false })
            }
        }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Palette.surface)
        .clickable(onClickLabel = "Where to watch") { open = true }
        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Icon(Icons.Default.Weekend, "Where to watch", Modifier.size(24.dp), tint = Palette.textSecondary)
        if (wide) {
            Text("Where to watch", style = TextStyle(fontSize = 12.sp, color = Palette.textMuted))
            Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
        }
    }
    }
}

/** The song playing: its cover and name (a pinch opens Now Playing), then pause and next. */
@Composable
private fun NowPlayingPill(state: AppState) {
    val music = app.lumiere.android.music.Music
    val song = music.current ?: return
    val server = music.server ?: state.server ?: return
    Row(Modifier.height(52.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.10f)).padding(start = 6.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.clip(RoundedCornerShape(50)).clickable(onClickLabel = "Now Playing") { state.push(Screen.NowPlaying) }.padding(end = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            coil.compose.AsyncImage(imageFor(song, server, CardShape.Poster, 120), null, contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier.size(40.dp).clip(RoundedCornerShape(50)).background(Palette.surface))
            Column(Modifier.width(150.dp)) {
                Text(song.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
                song.albumArtist?.let { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TextStyle(fontSize = 12.sp, color = Palette.textSecondary)) }
            }
        }
        TabPill(Row(if (music.isPlaying) "Pause" else "Play", if (music.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, false) { music.toggle() }, label = false)
        TabPill(Row("Next", Icons.Default.SkipNext, false) { music.next() }, label = false)
    }
}
