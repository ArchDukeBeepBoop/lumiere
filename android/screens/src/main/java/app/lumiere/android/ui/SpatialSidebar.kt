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
import androidx.compose.material.icons.filled.Anchor
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Crop169
import androidx.compose.material.icons.filled.Panorama
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Theaters
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
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
 * the private room; then the screen itself: larger, smaller, the room or
 * the cinema, bring it here, curved or flat, anchored in place. It works on the window's own
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
    Column(Modifier.frosted(40).verticalScroll(androidx.compose.foundation.rememberScrollState())
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
        Box(Modifier.size(28.dp, 1.dp).background(Color.White.copy(alpha = 0.12f)))
        val cinema = Stage.place == Stage.Place.CINEMA
        RailButton(Icons.Default.ZoomIn, if (cinema) "A row nearer" else "Larger", chosen = false) { Stage.larger() }
        RailButton(Icons.Default.ZoomOut, if (cinema) "A row back" else "Smaller", chosen = false) { Stage.smaller() }
        RailButton(if (cinema) Icons.Default.Weekend else Icons.Default.Theaters,
            if (cinema) "Back to your room" else "Cinema", chosen = cinema) { Stage.toggleCinema() }
        RailButton(Icons.Default.CenterFocusStrong, "Bring the screen here", chosen = false) { Stage.bringHere() }
        RailButton(if (Stage.curved) Icons.Default.Crop169 else Icons.Default.Panorama,
            if (Stage.curved) "Make the screen flat" else "Curve the screen round you", chosen = false) { Stage.toggleCurve() }
        // The sleep timer: each press the next step, its minutes shown under the moon.
        RailButton(Icons.Default.Bedtime, if (Stage.sleepMinutes == 0) "Sleep timer" else "Sleep in ${Stage.sleepMinutes} minutes",
            chosen = Stage.sleepMinutes > 0, caption = Stage.sleepMinutes.takeIf { it > 0 }?.toString()) { Stage.cycleSleep() }
        if (!cinema) RailButton(Icons.Default.Anchor,
            if (Stage.locked) "Release the screen" else "Anchor the screen here", chosen = Stage.locked) { Stage.toggleLock() }
    }
}

/** A round glass button; brighter where you point, filled when its screen is open. */
@Composable
private fun RailButton(icon: ImageVector, label: String, chosen: Boolean, caption: String? = null, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when {
        chosen -> Palette.textPrimary
        hovered -> Color.White.copy(alpha = 0.22f)
        else -> Color.Transparent
    }
    val ink = if (chosen) Palette.canvas else Palette.textPrimary
    Box(Modifier.size(48.dp).background(ground, CircleShape).hoverable(source)
        .clickable(interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = ink, modifier = Modifier.size(24.dp).then(if (caption != null) Modifier.padding(bottom = 10.dp) else Modifier))
        if (caption != null) androidx.compose.material3.Text(caption, color = ink,
            style = androidx.compose.ui.text.TextStyle(fontSize = 11.sp), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 6.dp))
    }
}
