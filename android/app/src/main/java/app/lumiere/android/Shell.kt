package app.lumiere.android

import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.sp
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.focus.focusRequester
import androidx.tv.material3.NavigationDrawerItem
import app.lumiere.android.ui.LocalFormFactor
import app.lumiere.android.ui.Palette

private data class Tab(val label: String, val icon: ImageVector, val screen: () -> Screen?, val owns: (Screen) -> Boolean)

private fun tabs(state: AppState, tv: Boolean): List<Tab> {
    val music = state.visibleViews(state.views).firstOrNull { it.collectionType == "music" }
    // The TV's tabs, as the Apple TV app's: Home, Library, Search — with Music
    // and Settings; favourites, collections, playlists and downloads live in Library.
    if (tv) return listOfNotNull(
        Tab("Home", Icons.Default.Home, { Screen.Home }, { it == Screen.Home }),
        Tab("Library", Icons.Default.VideoLibrary, { Screen.TvLibrary }, { it == Screen.TvLibrary }),
        Tab("Search", Icons.Default.Search, { Screen.Search }, { it == Screen.Search }),
        music?.let { m -> Tab("Music", Icons.Default.LibraryMusic, { Screen.Music(m) }, { it is Screen.Music }) },
        Tab("Settings", Icons.Default.Settings, { state.guarded { state.tab(Screen.Settings) }; null }, { it == Screen.Settings }),
    )
    return listOfNotNull(
        Tab("Home", Icons.Default.Home, { Screen.Home }, { it == Screen.Home }),
        Tab("Search", Icons.Default.Search, { Screen.Search }, { it == Screen.Search }),
        music?.let { m -> Tab("Music", Icons.Default.LibraryMusic, { Screen.Music(m) }, { it is Screen.Music }) },
        Tab("Favourites", Icons.Default.Star, { Screen.Favourites }, { it == Screen.Favourites }),
        Tab("Downloads", Icons.Default.Download, { Screen.Downloads }, { it == Screen.Downloads }),
        Tab("Settings", Icons.Default.Settings, { state.guarded { state.tab(Screen.Settings) }; null }, { it == Screen.Settings }),
    )
}

/**
 * The frame around every screen: a bar along the bottom on a phone, a rail
 * down the side on a TV (where a remote moves left into it), the mini player,
 * and a short slide between screens — forward going deeper, back coming out.
 */
@Composable
fun Shell(state: AppState, content: @Composable (Screen) -> Unit) {
    val form = LocalFormFactor.current
    val top = state.top
    val fullScreen = top is Screen.Player || top == Screen.NowPlaying
    val items = tabs(state, form.isTv)
    val context = androidx.compose.ui.platform.LocalContext.current
    androidx.compose.runtime.LaunchedEffect(state.settings.wallpaperColours) {
        app.lumiere.android.ui.MaterialYou.follow(context, state.settings.wallpaperColours, form.isTv)
    }
    // Clear of the status and navigation bars, except for the full-screen players.
    Row(Modifier.fillMaxSize().background(Palette.canvas)
        .then(if (fullScreen) Modifier else Modifier.systemBarsPadding())) {
        // On a TV the menu is hidden until Back on Home asks for it, so the
        // screen is the library and left never lands in the menu by accident.
        if (form.isTv && !fullScreen && state.tvMenuOpen && !state.settings.tvTopBar) {
            TvMenu(items, top, state)
        }
        Column(Modifier.weight(1f)) {
            // Wherever a screen opens or a panel closes, the remote lands on something:
            // if nothing holds focus a moment later, the first thing down the page takes it.
            var anyFocus by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
            val fm = androidx.compose.ui.platform.LocalFocusManager.current
            if (form.isTv) androidx.compose.runtime.LaunchedEffect(top, state.stack.size, state.actionsFor == null, state.tvMenuOpen) {
                kotlinx.coroutines.delay(450)
                if (!anyFocus && top !is Screen.Player) fm.moveFocus(androidx.compose.ui.focus.FocusDirection.Down)
            }
            Box(Modifier.weight(1f).onFocusChanged { anyFocus = it.hasFocus }) {
                // The player is never inside the transition: a video surface drawn
                // through an animation layer stays black on some TVs.
                if (top is Screen.Player) content(top) else AnimatedContent(
                    targetState = top to state.stack.size,
                    transitionSpec = {
                        val forward = targetState.second >= initialState.second
                        // A plain quick fade on a TV: sliding two screens costs frames a
                        // 2 GB box does not have.
                        if (app.lumiere.android.Motion.reduced) fadeIn(tween(0)).togetherWith(fadeOut(tween(0)))
                        else if (form.isTv) fadeIn(tween(120)).togetherWith(fadeOut(tween(90))) else
                        (slideInHorizontally(tween(260)) { w -> if (forward) w / 6 else -w / 6 } + fadeIn(tween(260)))
                            .togetherWith(slideOutHorizontally(tween(200)) { w -> if (forward) -w / 8 else w / 8 } + fadeOut(tween(200)))
                    },
                    label = "screens",
                ) { (screen, _) -> content(screen) }
                // On a TV the menu bar's Now Playing pill stands in for the bar along the bottom.
                if (!fullScreen && !form.isTv) app.lumiere.android.music.MiniPlayer(state)
                if (form.isTv && !fullScreen && state.settings.tvTopBar) {
                    androidx.compose.animation.AnimatedVisibility(state.tvMenuOpen || (top == Screen.Home && state.tvAtTop),
                        enter = androidx.compose.animation.slideInVertically { -it } + fadeIn(tween(150)),
                        exit = androidx.compose.animation.slideOutVertically { -it } + fadeOut(tween(120))) {
                        app.lumiere.android.tv.TvMenuBar(items.map { app.lumiere.android.tv.BarTab(it.label, it.screen, it.owns) }, top, state)
                    }
                }
                if (!fullScreen) app.lumiere.android.ui.NightDim(state)
            }
            if (!form.isTv && !fullScreen) {
                NavigationBar(containerColor = Palette.chrome) {
                    items.forEach { t ->
                        NavigationBarItem(
                            selected = t.owns(top), onClick = { t.screen()?.let(state::tab) },
                            icon = { Icon(t.icon, t.label) }, label = { Text(t.label, maxLines = 1, softWrap = false, overflow = androidx.compose.ui.text.style.TextOverflow.Visible,
                                fontSize = 11.sp) },
                            // Six tabs do not fit six labels on a phone: the selected one is named.
                            alwaysShowLabel = false,
                            colors = NavigationBarItemDefaults.colors(selectedIconColor = Palette.accent,
                                selectedTextColor = Palette.accent, unselectedIconColor = Palette.textSecondary,
                                unselectedTextColor = Palette.textSecondary, indicatorColor = Palette.surfaceRaised),
                        )
                    }
                }
            }
        }
    }
}

/**
 * The TV's menu: icons down the left edge that open into labels as the
 * remote moves in, and fold away again when it leaves — Compose for TV's
 * navigation drawer, so focus behaves the way Google TV's own menu does.
 */
@OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
@Composable
private fun TvMenu(items: List<Tab>, top: Screen, state: AppState) {
    val first = androidx.compose.runtime.remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.runtime.LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
    // Back from the menu: leave Lumiere, after asking.
    androidx.activity.compose.BackHandler { state.confirmExit = true }
    androidx.tv.material3.NavigationDrawer(
        drawerContent = { _ ->
            Column(Modifier.fillMaxHeight().background(Palette.chrome).padding(12.dp),
                verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp, androidx.compose.ui.Alignment.CenterVertically)) {
                items.forEachIndexed { i, t ->
                    NavigationDrawerItem(
                        modifier = if (t.owns(top) || (i == 0 && items.none { it.owns(top) })) Modifier.focusRequester(first) else Modifier,
                        selected = t.owns(top), onClick = { state.tvMenuOpen = false; t.screen()?.let(state::tab) },
                        leadingContent = { androidx.tv.material3.Icon(t.icon, null) },
                        colors = androidx.tv.material3.NavigationDrawerItemDefaults.colors(
                            contentColor = Palette.textSecondary, selectedContentColor = Palette.accent,
                            selectedContainerColor = Palette.surfaceRaised,
                            focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas,
                            focusedSelectedContainerColor = Palette.textPrimary, focusedSelectedContentColor = Palette.canvas,
                        ),
                    ) { androidx.tv.material3.Text(t.label) }
                }
            }
        },
        modifier = Modifier.fillMaxHeight(),
    ) { }
}
