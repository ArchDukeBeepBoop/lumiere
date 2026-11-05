package app.lumiere.android.tv

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.layout.height
import kotlinx.coroutines.launch
import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import app.lumiere.android.AppState
import app.lumiere.android.Screen
import app.lumiere.android.ui.Palette
import app.lumiere.android.ui.TvClock

data class BarTab(val label: String, val screen: () -> Screen?, val owns: (Screen) -> Boolean,
                  val icon: androidx.compose.ui.graphics.vector.ImageVector? = null)

/**
 * tvOS's menu bar: named tabs in a frosted capsule across the top of Home,
 * shown while the spotlight has the remote and reached by pressing up.
 *
 * Moving along it only moves the highlight; a tab, or the private room at its
 * right end, changes only when pressed. Down always lands back on the screen,
 * so the room can never be wandered into or become a place the remote is stuck.
 */
@Composable
fun TvMenuBar(tabs: List<BarTab>, top: Screen, state: AppState) {
    val first = remember { FocusRequester() }
    val focus = LocalFocusManager.current
    val activity = LocalContext.current as? android.app.Activity
    val ctx = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var installing by remember { mutableStateOf(false) }
    LaunchedEffect(state.tvMenuOpen) {
        if (state.tvMenuOpen) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    }
    if (state.tvMenuOpen) androidx.activity.compose.BackHandler { state.confirmExit = true }
    fun leave() { state.tvMenuOpen = false; focus.moveFocus(FocusDirection.Right) }
    // The Mac app's sidebar, as a TV menu: one frosted capsule down the left edge —
    // the clock, the tabs, then what is playing, an update, and the private room.
    // Up and Down move along it; Right or Back puts it away.
    Box(Modifier.fillMaxHeight()
        .background(Brush.horizontalGradient(listOf(Palette.canvas.copy(alpha = 0.85f), Palette.canvas.copy(alpha = 0f))))
        .onPreviewKeyEvent { e ->
            val down = e.nativeKeyEvent.action == KeyEvent.ACTION_DOWN
            if (down && e.nativeKeyEvent.keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) { leave(); true } else false
        }
        .padding(start = 24.dp, end = 48.dp, top = 24.dp, bottom = 24.dp), contentAlignment = Alignment.CenterStart) {
        androidx.compose.foundation.layout.Column(Modifier.width(220.dp).clip(RoundedCornerShape(28.dp))
            .background(androidx.compose.ui.graphics.lerp(Palette.surface, app.lumiere.android.ui.Ambient.colour ?: Palette.surface, 0.35f).copy(alpha = 0.82f))
            .padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(Modifier.padding(start = 14.dp, top = 4.dp, bottom = 8.dp)) { TvClock(state) }
            // Where Home's remote is, in a word: the row and how far down.
            state.homePosition?.takeIf { top == Screen.Home }?.let {
                androidx.compose.material3.Text(it, color = Palette.textMuted, style = androidx.compose.material3.MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(start = 14.dp, bottom = 6.dp))
            }
            tabs.forEachIndexed { i, t ->
                val here = t.owns(top) || (i == 0 && tabs.none { it.owns(top) })
                Pill(t.label, t.owns(top), Modifier.fillMaxWidth().then(if (here) Modifier.focusRequester(first) else Modifier), state.tvMenuOpen,
                    icon = t.icon?.let { ic -> { Icon(ic, null, Modifier.size(20.dp)) } }) {
                    state.tvMenuOpen = false; t.screen()?.let(state::tab)
                }
            }
            Box(Modifier.padding(vertical = 6.dp).fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))
            // Only while music actually plays: one press to its full screen.
            if (app.lumiere.android.music.Music.isPlaying)
                Pill("Now Playing", true, Modifier.fillMaxWidth(), state.tvMenuOpen, icon = { Icon(app.lumiere.android.ui.Symbols.note, null, Modifier.size(20.dp)) }) { state.tvMenuOpen = false; state.push(Screen.NowPlaying) }
            // The update installs from here: fetched, then Android's own install prompt.
            state.updateReady?.let { name ->
                Pill(if (installing) "Fetching $name…" else "Update to $name", true, Modifier.fillMaxWidth(), state.tvMenuOpen) {
                    val srv = state.server
                    if (!installing && srv != null && ctx != null) {
                        installing = true
                        scope.launch { app.lumiere.android.Updater.install(ctx, srv)?.let { installing = false } }
                    }
                }
            }
            if (state.privateLibraries.isNotEmpty() && activity != null) {
                Pill(if (state.roomOpen) "Leave Private" else "Private", state.roomOpen, Modifier.fillMaxWidth(), state.tvMenuOpen,
                    icon = { Icon(if (state.roomOpen) Icons.Default.LockOpen else Icons.Default.Lock, null, Modifier.size(18.dp)) }) {
                    state.tvMenuOpen = false
                    state.tab(Screen.Home)
                    app.lumiere.android.ui.toggleRoom(state, activity)
                }
            }
        }
    }
}

/** The bar's capsule; only reachable once the bar is opened, so moving right past More Info stays put. */
@Composable
private fun Pill(label: String, selected: Boolean, modifier: Modifier, open: Boolean, icon: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    // A soft glow behind the current tab, as tvOS lights the tab you are on.
    app.lumiere.android.ui.TvPill(onClick, modifier.focusProperties { canFocus = open }
        .then(if (selected) Modifier.drawBehind {
            drawCircle(androidx.compose.ui.graphics.Brush.radialGradient(listOf(Color.White.copy(alpha = 0.16f), Color.Transparent),
                center = center, radius = size.width * 0.75f), radius = size.width * 0.75f)
        } else Modifier), selected,
        if (selected) Palette.textPrimary else Palette.textSecondary) {
        if (icon != null) { icon(); Spacer(Modifier.width(6.dp)) }
        androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, style = androidx.tv.material3.MaterialTheme.typography.titleSmall)
            // tvOS's mark under the current tab, when the remote is elsewhere.
            if (selected && !app.lumiere.android.ui.LocalPillFocused.current)
                Box(Modifier.padding(top = 3.dp).width(18.dp).height(2.dp).background(Palette.textPrimary, RoundedCornerShape(1.dp)))
        }
    }
}
