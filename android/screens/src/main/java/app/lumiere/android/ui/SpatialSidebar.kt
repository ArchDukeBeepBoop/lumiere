package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.SatelliteAlt
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Theaters
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Cabin
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.SettingsRemote
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.OpenApp
import app.lumiere.android.Stage
import app.lumiere.android.tabs

/**
 * visionOS's tab bar, for the Quest: a column of glass beside Lumiere's
 * window, carried with it. Home, Library, Search, Music and Settings, and
 * the private room; the poster wall; the room or the cinema (and its rows);
 * everything brought back in front of you; the sleep timer. It is a panel
 * of its own, with a grab bar: put it wherever suits you. It works on the window's own
 * state, so a tab here is the same as one from the TV's menu.
 */
@Composable
fun SpatialSidebar(activity: android.app.Activity) {
    LumiereTheme {
        val state = OpenApp.state
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            // Not behind "Who's watching?": nobody's tabs until someone is chosen.
            if (state != null && state.session != null && !state.choosing) Rail(state, activity)
        }
    }
}

@Composable
private fun Rail(state: AppState, activity: android.app.Activity) {
    val top = state.top
    // Fourteen buttons in the rail's 800 dp; it scrolls rather than clips if more ever come.
    Column(Modifier.spatialGlass(40).verticalScroll(androidx.compose.foundation.rememberScrollState())
        .padding(vertical = 12.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        tabs(state, tv = true).forEach { tab ->
            RailButton(tab.icon, tab.label, chosen = tab.owns(top)) { tab.screen()?.let(state::tab) }
        }
        Box(Modifier.size(28.dp, 1.dp).background(Color.White.copy(alpha = 0.12f)))
        RailButton(if (state.roomOpen) Icons.Default.LockOpen else Icons.Default.Lock,
            if (state.roomOpen) "Leave the private room" else "Private room", chosen = state.roomOpen) {
            toggleRoom(state, activity)
        }
        // Music, whenever there's a song (playing or paused): its cover opens the player; play/pause; next.
        MusicGroup(state)
        // Who's watching: their picture; pressed, "Who's watching?". Never while a film plays.
        if (state.top !is app.lumiere.android.Screen.Player && !app.lumiere.android.player.Theater.active)
            ProfileGlassButton(state.currentProfile) { state.askWhoIsWatching() }
        // Diagnostics, always (a plain start too): which build this is, and what works.
        RailButton(Icons.Default.BugReport, "Diagnostics: ${app.lumiere.android.AppBuild.stamp}",
            chosen = top is app.lumiere.android.Screen.DiagnosticsView, caption = "Check") { state.push(app.lumiere.android.Screen.DiagnosticsView) }
        // The spatial buttons, only while the headset's director runs; a plain start (after
        // starts that failed) has none, and they would do nothing there.
        if (!Stage.directed) return@Column
        Box(Modifier.size(28.dp, 1.dp).background(Color.White.copy(alpha = 0.12f)))
        // Where you are: your room, the cinema (you're in its hall at once), the dark. The window
        // itself resizes from its corners and moves by its bar, as Quest windows do.
        RailButton(placeIcon(Stage.place), "You're in ${Stage.place.label}: change", chosen = false,
            caption = placeCaption(Stage.place)) { Stage.nextPlace() }
        // Away from your room, back to the handset near your hands (the whole window stays for your room).
        if ((Stage.place != Stage.Place.ROOM || Stage.mount != null) && Handset.enabled && Stage.wholeWindow)
            RailButton(Icons.Default.SettingsRemote, "Back to the handset", chosen = false, caption = "Handset") { Stage.wholeWindow = false }
        // In your room, the big screen onto the wall you're facing (or off it again): films play there from then on.
        if (Stage.place == Stage.Place.ROOM)
            RailButton(Icons.Default.Tv, if (Stage.mount != null) "Take the screen off your wall" else "Put the screen on the wall you're facing",
                chosen = Stage.mount != null, caption = "Wall") { Stage.askMount() }
        if (PosterWall.enabled) RailButton(Icons.Default.ViewModule, "Poster wall", chosen = PosterWall.open) { PosterWall.open = !PosterWall.open }
        RailButton(Icons.Default.CenterFocusStrong, "Bring everything here", chosen = false) { Stage.bringHere() }
        // The place's own sounds (the fire, the lake at night): on or off.
        RailButton(Icons.Default.GraphicEq, if (Stage.ambience) "Sounds of the place: on" else "Sounds of the place: off",
            chosen = Stage.ambience) { Stage.toggleAmbience() }
        // The sleep timer: each press the next step, its minutes shown under the moon.
        RailButton(Icons.Default.Bedtime, if (Stage.sleepMinutes == 0) "Sleep timer" else "Sleep in ${Stage.sleepMinutes} minutes",
            chosen = Stage.sleepMinutes > 0, caption = Stage.sleepMinutes.takeIf { it > 0 }?.toString()) { Stage.cycleSleep() }

    }
}

/** The song now, in the tab bar or the handset: its cover (to open the player), play/pause, next. Nothing without a song. */
@Composable
fun MusicGroup(state: AppState, size: androidx.compose.ui.unit.Dp = 48.dp) {
    val track = app.lumiere.android.music.Music.current ?: return
    val server = state.server ?: return
    val playing = app.lumiere.android.music.Music.isPlaying
    Box(Modifier.size(28.dp, 1.dp).background(Color.White.copy(alpha = 0.12f)))
    val source = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    Box(Modifier.size(size).clip(androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
        .clickable(interactionSource = source, indication = null) {
            if (Stage.place != Stage.Place.ROOM) Stage.wholeWindow = true
            state.push(app.lumiere.android.Screen.NowPlaying)
        }) {
        WithAppImages {
            coil.compose.AsyncImage(server.imageUrl(track.albumId ?: track.id, "Primary", null, 160), "Now playing: ${track.name}",
                contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.matchParentSize())
        }
    }
    GlassButton(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause the music" else "Play the music",
        chosen = playing, size = size) { app.lumiere.android.music.Music.toggle() }
    GlassButton(Icons.Default.SkipNext, "Next song", size = size) { app.lumiere.android.music.Music.next() }
}

/** The tab bar's buttons: the Quest panels' glass button. */
@Composable
private fun RailButton(icon: ImageVector, label: String, chosen: Boolean, caption: String? = null, onClick: () -> Unit) =
    GlassButton(icon, label, chosen, caption, onClick = onClick)

/** Each place's icon: a sofa for your room, a film strip for the cinema, a cabin, hills for the lakeside, a moon for the dark. */
fun placeIcon(place: Stage.Place): ImageVector = when (place) {
    Stage.Place.ROOM -> Icons.Default.Weekend
    Stage.Place.CINEMA -> Icons.Default.Theaters
    Stage.Place.CABIN -> Icons.Default.Cabin
    Stage.Place.LAKE -> Icons.Default.Landscape
    Stage.Place.CLOUDS -> Icons.Default.Cloud
    Stage.Place.MOON -> Icons.Default.NightsStay
    Stage.Place.STATION -> Icons.Default.SatelliteAlt
    Stage.Place.VOID -> Icons.Default.DarkMode
    Stage.Place.SPACE -> Icons.Default.AutoAwesome
    Stage.Place.DRIVE_IN -> Icons.Default.DirectionsCar
    Stage.Place.PALACE -> Icons.Default.TheaterComedy
    Stage.Place.ROOFTOP -> Icons.Default.LocationCity
    Stage.Place.WINTER -> Icons.Default.AcUnit
    Stage.Place.SEA -> Icons.Default.Waves
}

/** Each place in a word short enough for a 48 dp button ("Lakeside" wouldn't fit under its icon). */
fun placeCaption(place: Stage.Place): String = when (place) {
    Stage.Place.ROOM -> "Room"
    Stage.Place.CINEMA -> "Cinema"
    Stage.Place.CABIN -> "Cabin"
    Stage.Place.LAKE -> "Lake"
    Stage.Place.CLOUDS -> "Clouds"
    Stage.Place.MOON -> "Moon"
    Stage.Place.STATION -> "Station"
    Stage.Place.VOID -> "Dark"
    Stage.Place.SPACE -> "Space"
    Stage.Place.DRIVE_IN -> "Drive-in"
    Stage.Place.PALACE -> "Palace"
    Stage.Place.ROOFTOP -> "Rooftop"
    Stage.Place.WINTER -> "Winter"
    Stage.Place.SEA -> "Sea"
}
