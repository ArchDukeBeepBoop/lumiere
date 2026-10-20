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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.clickable
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
    // The phone's tabs, as the Apple TV app on an iPhone: Home, Library, Search —
    // with Music. Downloads, favourites, collections, playlists and Settings live in Library.
    return listOfNotNull(
        Tab("Home", Icons.Default.Home, { Screen.Home }, { it == Screen.Home }),
        Tab("Library", Icons.Default.VideoLibrary, { Screen.PhoneLibrary }, { it == Screen.PhoneLibrary }),
        music?.let { m -> Tab("Music", Icons.Default.LibraryMusic, { Screen.Music(m) }, { it is Screen.Music }) },
        Tab("Search", Icons.Default.Search, { Screen.Search }, { it == Screen.Search }),
    )
}

/** Phone screens drawn under the status bar: their artwork runs to the top edge, as Apple's do. */
private fun edgeToEdge(screen: Screen) = screen == Screen.Home || screen is Screen.Detail

/**
 * The frame around every screen: a bar along the bottom on a phone, a rail
 * down the side on a TV (where a remote moves left into it), the mini player,
 * and a short slide between screens — forward going deeper, back coming out.
 */
@Composable
fun Shell(state: AppState, content: @Composable (Screen) -> Unit) {
    val form = LocalFormFactor.current
    val top = state.top
    val fullScreen = top is Screen.Player || top == Screen.NowPlaying || top is Screen.LocalFile
    val items = tabs(state, form.isTv)
    val context = androidx.compose.ui.platform.LocalContext.current
    androidx.compose.runtime.LaunchedEffect(state.settings.wallpaperColours) {
        app.lumiere.android.ui.MaterialYou.follow(context, state.settings.wallpaperColours, form.isTv)
    }
    // Clear of the status and navigation bars, except for the full-screen players.
    // On a phone each screen keeps clear of the status bar itself, so Home and
    // a title's page can run their artwork up under it.
    Row(Modifier.fillMaxSize().background(Palette.canvas)
        .then(if (fullScreen) Modifier else if (form.isTv) Modifier.systemBarsPadding()
            else Modifier.navigationBarsPadding())) {
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
                    targetState = Triple(top, state.stack.size, state.stack.getOrNull(1)),
                    transitionSpec = {
                        val forward = targetState.second >= initialState.second
                        // Another tab: swapped, not pushed, as iOS does.
                        val tabSwitch = !form.isTv && targetState.third != initialState.third &&
                            targetState.second <= 2 && initialState.second <= 2
                        // A plain quick fade on a TV: sliding two screens costs frames a
                        // 2 GB box does not have.
                        if (app.lumiere.android.Motion.reduced) fadeIn(tween(0)).togetherWith(fadeOut(tween(0)))
                        else if (tabSwitch) fadeIn(tween(140)).togetherWith(fadeOut(tween(90)))
                        // tvOS between tabs: the page eases sideways toward the tab chosen, a short way.
                        else if (form.isTv && targetState.third != initialState.third && targetState.second <= 2 && initialState.second <= 2) {
                            fun tabOf(x: Screen?) = items.indexOfFirst { t -> t.owns(x ?: Screen.Home) }.coerceAtLeast(0)
                            val forward = tabOf(targetState.third) >= tabOf(initialState.third)
                            (slideInHorizontally(tween(260)) { w -> if (forward) w / 14 else -w / 14 } + fadeIn(tween(220)))
                                .togetherWith(slideOutHorizontally(tween(200)) { w -> if (forward) -w / 14 else w / 14 } + fadeOut(tween(150)))
                        }
                        else if (form.isTv) fadeIn(tween(120)).togetherWith(fadeOut(tween(90))) else {
                            // iOS's push: the new page slides in whole from the right over the
                            // last, which drifts a third left and dims; back reverses it.
                            val ease = androidx.compose.animation.core.CubicBezierEasing(0.2f, 0.9f, 0.3f, 1f)
                            if (forward) (slideInHorizontally(tween(340, easing = ease)) { w -> w })
                                .togetherWith(slideOutHorizontally(tween(340, easing = ease)) { w -> -w / 3 } + fadeOut(tween(340), 0.5f))
                                .apply { targetContentZIndex = 1f }
                            else (slideInHorizontally(tween(320, easing = ease)) { w -> -w / 3 } + fadeIn(tween(320), 0.5f))
                                .togetherWith(slideOutHorizontally(tween(320, easing = ease)) { w -> w })
                                .apply { targetContentZIndex = -1f }
                        }
                    },
                    label = "screens",
                ) { (screen, _, _) ->
                    if (form.isTv || screen is Screen.Player || screen == Screen.NowPlaying || edgeToEdge(screen)) content(screen)
                    else Box(Modifier.statusBarsPadding()) { content(screen) }
                }
                // On a TV the menu bar's Now Playing pill stands in for the bar along the bottom.
                if (!fullScreen && !form.isTv) { app.lumiere.android.music.MiniPlayer(state); app.lumiere.android.local.LocalMiniBar(state) }
                if (form.isTv && !fullScreen && state.settings.tvTopBar) {
                    androidx.compose.animation.AnimatedVisibility(state.tvMenuOpen || (top == Screen.Home && state.tvAtTop),
                        enter = androidx.compose.animation.slideInVertically { -it } + fadeIn(tween(150)),
                        exit = androidx.compose.animation.slideOutVertically { -it } + fadeOut(tween(120))) {
                        app.lumiere.android.tv.TvMenuBar(items.map { app.lumiere.android.tv.BarTab(it.label, it.screen, it.owns) }, top, state)
                    }
                }
                if (!fullScreen) app.lumiere.android.ui.NightDim(state)
            }
            if (!form.isTv && !fullScreen) PhoneTabBar(items, top, state)
        }
    }
}

/**
 * iOS's tab bar: near-black under a hairline, every tab named in small type,
 * the current one in the accent. The tab is the one whose pages you are in,
 * so a title opened from Library keeps Library lit, and Settings opened from
 * Home keeps Home lit.
 */
@Composable
private fun PhoneTabBar(items: List<Tab>, top: Screen, state: AppState) {
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    // The tab whose first page the stack began from; anything opened from Home —
    // Settings from the account button, a title — keeps Home lit.
    val root = state.stack.getOrNull(1) ?: Screen.Home
    val current = items.firstOrNull { it.owns(root) } ?: items.first()
    Column(Modifier.fillMaxWidth().background(Palette.chrome.copy(alpha = 0.97f))) {
        androidx.compose.material3.HorizontalDivider(thickness = 0.5.dp, color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.1f))
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 4.dp)) {
            items.forEach { t ->
                val on = t == current
                Column(Modifier.weight(1f).clickable(androidx.compose.runtime.remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null) {
                    haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                    // Tapping the tab you are in goes back to its first page, as iOS does.
                    t.screen()?.let(state::tab)
                }, horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                    Icon(t.icon, t.label, tint = if (on) Palette.accent else Palette.textMuted,
                        modifier = Modifier.padding(bottom = 2.dp).then(Modifier.size(26.dp)))
                    Text(t.label, fontSize = 10.sp, maxLines = 1, color = if (on) Palette.accent else Palette.textMuted,
                        fontWeight = androidx.compose.ui.text.font.FontWeight.Medium)
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
