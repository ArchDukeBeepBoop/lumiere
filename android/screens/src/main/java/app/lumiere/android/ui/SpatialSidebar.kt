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
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Theaters
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.DarkMode
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
            if (state != null && state.session != null) Rail(state, activity)
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
        // The spatial buttons, only while the headset's director runs; a plain start (after
        // starts that failed) has none, and they would do nothing there.
        if (!Stage.directed) return@Column
        Box(Modifier.size(28.dp, 1.dp).background(Color.White.copy(alpha = 0.12f)))
        // Where you are: your room, the cinema (you're in its hall at once), the dark. The window
        // itself resizes from its corners and moves by its bar, as Quest windows do.
        RailButton(placeIcon(Stage.place), "You're in ${Stage.place.label}: change", chosen = false,
            caption = placeCaption(Stage.place)) { Stage.nextPlace() }
        if (PosterWall.enabled) RailButton(Icons.Default.ViewModule, "Poster wall", chosen = PosterWall.open) { PosterWall.open = !PosterWall.open }
        RailButton(Icons.Default.CenterFocusStrong, "Bring everything here", chosen = false) { Stage.bringHere() }
        // The sleep timer: each press the next step, its minutes shown under the moon.
        RailButton(Icons.Default.Bedtime, if (Stage.sleepMinutes == 0) "Sleep timer" else "Sleep in ${Stage.sleepMinutes} minutes",
            chosen = Stage.sleepMinutes > 0, caption = Stage.sleepMinutes.takeIf { it > 0 }?.toString()) { Stage.cycleSleep() }

    }
}

/** The tab bar's buttons: the Quest panels' glass button. */
@Composable
private fun RailButton(icon: ImageVector, label: String, chosen: Boolean, caption: String? = null, onClick: () -> Unit) =
    GlassButton(icon, label, chosen, caption, onClick = onClick)

/** Each place's icon: a sofa for your room, a film strip for the cinema, a moon for the dark. */
fun placeIcon(place: Stage.Place): ImageVector = when (place) {
    Stage.Place.ROOM -> Icons.Default.Weekend
    Stage.Place.CINEMA -> Icons.Default.Theaters
    Stage.Place.VOID -> Icons.Default.DarkMode
    Stage.Place.SPACE -> Icons.Default.AutoAwesome
}

fun placeCaption(place: Stage.Place): String = when (place) {
    Stage.Place.ROOM -> "Room"
    Stage.Place.CINEMA -> "Cinema"
    Stage.Place.VOID -> "Dark"
    Stage.Place.SPACE -> "Space"
}
