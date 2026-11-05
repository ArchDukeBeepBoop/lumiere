package app.lumiere.android.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput

/**
 * The Quest's window has the TV's layout and a pointer. Compose for TV's
 * buttons, chips, pills, surfaces and drawer items answer only a remote's
 * OK — they have no pointer input at all — so a pinch or a trigger on them
 * did nothing, Sign In first. These hear the pointer for them on a Quest
 * and add nothing on the TV (no pointer) or the phone (its own buttons).
 */
private val pointerAware get() = app.lumiere.android.Flavor.quest

/** A pinch or trigger on this clicks it. */
@Composable
fun Modifier.pointerTap(enabled: Boolean = true, onClick: () -> Unit): Modifier {
    if (!pointerAware || !enabled) return this
    val latest by rememberUpdatedState(onClick)
    return pointerInput(Unit) { detectTapGestures(onTap = { latest() }) }
}

/**
 * Pointing at this focuses it, as the remote would, so it lights before it's
 * pinched — Horizon OS asks every control to show a hover state.
 */
@Composable
fun Modifier.hoverFocuses(): Modifier {
    if (!pointerAware) return this
    val focus = remember { FocusRequester() }
    return focusRequester(focus).pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) {
                val event = awaitPointerEvent()
                if (event.type == PointerEventType.Enter) runCatching { focus.requestFocus() }
            }
        }
    }
}

/** Both: lights when pointed at, clicks when pinched. */
@Composable
fun Modifier.pointable(enabled: Boolean = true, onClick: () -> Unit): Modifier =
    pointerTap(enabled, onClick).hoverFocuses()
