package app.lumiere.android.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusProperties
import androidx.compose.foundation.focusGroup
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface

/**
 * tvOS's capsule, the menu bar's look everywhere a remote picks from a list:
 * clear at rest, frosted when it is the current choice, white with dark text
 * when the remote is on it. No ring; the fill is the focus.
 */
@Composable
fun TvPill(onClick: () -> Unit, modifier: Modifier = Modifier, selected: Boolean = false,
           tint: Color = Palette.textPrimary, shape: Shape = RoundedCornerShape(50),
           content: @Composable RowScope.() -> Unit) {
    var focused by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    Surface(onClick = onClick, modifier = modifier.questTarget().pointerTap(onClick = onClick).hoverFocuses().onFocusChanged { focused = it.isFocused },
        shape = ClickableSurfaceDefaults.shape(shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = if (selected) Palette.surfaceRaised else Color.Transparent,
            contentColor = tint,
            focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas,
        )) {
        // The theme's text styles carry their own colours, which stayed white on
        // the white focused pill; inside one they follow the pill instead.
        val t = androidx.compose.material3.MaterialTheme.typography
        fun TextStyleU(s: androidx.compose.ui.text.TextStyle) = s.copy(color = Color.Unspecified)
        val plain = t.copy(titleLarge = TextStyleU(t.titleLarge), titleMedium = TextStyleU(t.titleMedium), titleSmall = TextStyleU(t.titleSmall),
            bodyLarge = TextStyleU(t.bodyLarge), bodyMedium = TextStyleU(t.bodyMedium), bodySmall = TextStyleU(t.bodySmall),
            labelLarge = TextStyleU(t.labelLarge), labelMedium = TextStyleU(t.labelMedium).copy(), labelSmall = TextStyleU(t.labelSmall))
        androidx.compose.material3.MaterialTheme(colorScheme = androidx.compose.material3.MaterialTheme.colorScheme, typography = plain) {
        CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides androidx.tv.material3.LocalContentColor.current,
            LocalPillFocused provides focused) {
            Row(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, content = content)
        }
        }
    }
}

/**
 * After a held OK opens a menu, the release — and the repeats still arriving —
 * belong to the hold, not to whatever the menu focused first. Swallowed until
 * a fresh press begins.
 */
@Composable
fun Modifier.ignoreHeldOk(): Modifier {
    val fresh = androidx.compose.runtime.remember { booleanArrayOf(false) }
    return this.onPreviewKeyEvent { e ->
        val k = e.nativeKeyEvent
        val ok = k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_CENTER || k.keyCode == android.view.KeyEvent.KEYCODE_ENTER ||
            k.keyCode == android.view.KeyEvent.KEYCODE_NUMPAD_ENTER
        when {
            !ok || fresh[0] -> false
            k.action == android.view.KeyEvent.ACTION_DOWN && k.repeatCount == 0 -> { fresh[0] = true; false }
            else -> true
        }
    }
}

/** Whether the pill around this content has the remote: coloured values turn dark with the text. */
val LocalPillFocused = androidx.compose.runtime.compositionLocalOf { false }

/** [colour] at rest; the pill's own dark text once the remote is on it, so gold or red never sits on white. */
@Composable
fun pillTint(colour: Color): Color =
    if (LocalPillFocused.current) androidx.compose.material3.LocalContentColor.current else colour

/**
 * A title's facts as Apple prints them under its name: the rating and the
 * length in small outlined capsules, the rest as plain words between.
 */
@Composable
fun FactPills(year: String?, length: String?, rating: String?, rest: List<String>) {
    androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        val plain = androidx.compose.ui.text.TextStyle(fontSize = 15.sp, color = Color.White.copy(alpha = 0.9f))
        year?.let { androidx.compose.material3.Text(it, style = plain) }
        listOfNotNull(rating, length).forEach {
            androidx.compose.material3.Text(it, style = plain.copy(fontSize = 13.sp), modifier = Modifier
                .border(1.dp, Color.White.copy(alpha = 0.6f), RoundedCornerShape(5.dp)).padding(horizontal = 7.dp, vertical = 2.dp))
        }
        if (rest.isNotEmpty()) androidx.compose.material3.Text(rest.joinToString("  ·  "), style = plain, maxLines = 1)
    }
}

/**
 * A dialog's hold on the remote: the D-pad moves only among its own controls
 * and never slips to the screen behind — the PIN pad lost the remote to
 * Settings underneath. Put on the dialog's panel.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
fun Modifier.holdsRemote(): Modifier = this
    .focusProperties { exit = { androidx.compose.ui.focus.FocusRequester.Cancel } }
    .focusGroup()
