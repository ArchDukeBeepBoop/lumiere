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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Theaters
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.lumiere.android.AppState
import app.lumiere.android.OpenApp
import app.lumiere.android.Stage
import app.lumiere.android.tabs

/**
 * visionOS's tab bar, for the Quest: a column of glass beside Lumiere's
 * window, carried with it. Home, Library, Search, Music and Settings, and
 * the private room; then the screen itself: larger, smaller, the room or
 * the cinema, bring it here, pin it in place. It works on the window's own
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
    Column(Modifier.frosted(40).padding(vertical = 14.dp, horizontal = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
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
        if (!cinema) RailButton(if (Stage.locked) Icons.Default.PushPin else Icons.Outlined.PushPin,
            if (Stage.locked) "Unpin the screen" else "Pin the screen in place", chosen = Stage.locked) { Stage.toggleLock() }
    }
}

/** A round glass button; brighter where you point, filled when its screen is open. */
@Composable
private fun RailButton(icon: ImageVector, label: String, chosen: Boolean, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    val ground = when {
        chosen -> Palette.textPrimary
        hovered -> Color.White.copy(alpha = 0.22f)
        else -> Color.Transparent
    }
    Box(Modifier.size(56.dp).background(ground, CircleShape).hoverable(source)
        .clickable(interactionSource = source, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = if (chosen) Palette.canvas else Palette.textPrimary, modifier = Modifier.size(26.dp))
    }
}
