package app.lumiere.android.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput

/**
 * On a Quest, pointing at something focuses it, as the remote moving there
 * would on a TV: the controller's ray or your hand gets the same lift, ring
 * and passing light as the remote does, and a pinch then presses it.
 * Elsewhere it changes nothing.
 */
@Composable
fun Modifier.hoverFocuses(): Modifier {
    if (!app.lumiere.android.AppBuild.quest) return this
    val me = remember { FocusRequester() }
    return focusRequester(me).hoverFocuses(me)
}

/** As above, for something that already has its own [FocusRequester]. */
@Composable
fun Modifier.hoverFocuses(requester: FocusRequester): Modifier {
    if (!app.lumiere.android.AppBuild.quest) return this
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    LaunchedEffect(hovered) { if (hovered) runCatching { requester.requestFocus() } }
    return hoverable(source)
}

/**
 * Compose for TV's buttons, chips and pills answer only a remote's OK; a
 * Quest's pinch or trigger arrives as a pointer tap, which they never hear,
 * so on a Quest they did nothing at all. This hears the tap for them. Phones
 * use their own buttons and TVs have no pointer, so elsewhere it adds nothing.
 */
@Composable
fun Modifier.pointerTap(enabled: Boolean = true, onClick: () -> Unit): Modifier {
    if (!app.lumiere.android.AppBuild.quest || !enabled) return this
    val latest by rememberUpdatedState(onClick)
    return pointerInput(Unit) { detectTapGestures(onTap = { latest() }) }
}
