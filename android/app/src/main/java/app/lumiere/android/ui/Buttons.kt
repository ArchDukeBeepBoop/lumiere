@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)

package app.lumiere.android.ui

import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.tv.material3.Border
import androidx.tv.material3.ButtonDefaults as TvButtonDefaults
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.FilterChipDefaults as TvChipDefaults
import androidx.tv.material3.IconButtonDefaults as TvIconDefaults

/**
 * The app's buttons and chips. On a phone they are Material's; on a TV they
 * are Compose for TV's, which grow, brighten and take a white ring when the
 * remote is on them — the selected one must be plain from across the room,
 * and Material's touch styling barely changed at all.
 */

/** Material's Text reads Material's content colour; inside a TV control it must follow the TV one. */
@Composable
private fun TvColour(content: @Composable () -> Unit) =
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.material3.LocalContentColor provides androidx.tv.material3.LocalContentColor.current,
        content = content,
    )

private val ring get() = Border(BorderStroke(2.dp, Color.White), shape = RoundedCornerShape(50))

@Composable
fun LButton(onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = true, enabled: Boolean = true,
            tint: Color? = null, content: @Composable RowScope.() -> Unit) {
    if (!LocalFormFactor.current.isTv) {
        // The phone's: Apple's capsule — white with dark words for the main action, frosted grey otherwise.
        val fg = if (primary) Color.Black else Color.White
        androidx.compose.foundation.layout.Row(modifier.heightIn(min = 44.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (primary) (tint ?: Color.White).copy(alpha = if (enabled) 1f else 0.4f) else Color.White.copy(alpha = if (enabled) 0.14f else 0.07f))
            .then(if (enabled) Modifier.iosClick(onClick) else Modifier).padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides fg,
                androidx.compose.material3.LocalTextStyle provides IosType.headline.copy(color = fg)) { content() }
        }
        return
    }
    androidx.tv.material3.Button(
        onClick = onClick, modifier = modifier, enabled = enabled,
        scale = TvButtonDefaults.scale(focusedScale = 1.06f),
        colors = TvButtonDefaults.colors(
            containerColor = if (primary) (tint ?: Palette.accent) else Palette.surfaceRaised.copy(alpha = 0.72f),
            contentColor = if (primary) Palette.onAccent else Palette.textPrimary,
            focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas,
        ),
    ) { TvColour { androidx.compose.foundation.layout.Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) { content() } } }
}

@Composable
fun LTextButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                content: @Composable RowScope.() -> Unit) {
    if (!LocalFormFactor.current.isTv) {
        // iOS's plain button: words in the accent, no box.
        androidx.compose.foundation.layout.Row(modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(8.dp))
            .then(if (enabled) Modifier.iosClick(onClick) else Modifier).padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            val c = Palette.accent.copy(alpha = if (enabled) 1f else 0.4f)
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides c,
                androidx.compose.material3.LocalTextStyle provides IosType.headline.copy(color = c)) { content() }
        }
        return
    }
    LButton(onClick, modifier, primary = false, enabled = enabled, content = content)
}

@Composable
fun LChip(selected: Boolean, onClick: () -> Unit, label: @Composable () -> Unit, modifier: Modifier = Modifier) {
    if (!LocalFormFactor.current.isTv) {
        // iOS's capsule filter, as IosChip.
        val fg = if (selected) Color.Black else Palette.textPrimary
        androidx.compose.foundation.layout.Box(modifier.clip(RoundedCornerShape(50)).background(if (selected) Color.White else Palette.surface)
            .iosClick(onClick).padding(horizontal = 14.dp, vertical = 7.dp)) {
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides fg,
                androidx.compose.material3.LocalTextStyle provides IosType.footnote.copy(color = fg,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)) { label() }
        }
        return
    }
    androidx.tv.material3.FilterChip(
        selected = selected, onClick = onClick, modifier = modifier,
        scale = TvChipDefaults.scale(focusedScale = 1.1f),
        colors = TvChipDefaults.colors(
            containerColor = Color.Transparent, contentColor = Palette.textSecondary,
            selectedContainerColor = Palette.surfaceRaised, selectedContentColor = Palette.textPrimary,
            focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas,
            focusedSelectedContainerColor = Palette.textPrimary, focusedSelectedContentColor = Palette.canvas,
        ),
    ) { TvColour(label) }
}

@Composable
fun LIconButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                content: @Composable BoxScope.() -> Unit) {
    if (!LocalFormFactor.current.isTv) {
        androidx.compose.material3.IconButton(onClick, modifier, enabled) { androidx.compose.foundation.layout.Box(content = content) }
        return
    }
    var focused by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    androidx.tv.material3.IconButton(
        onClick = onClick, modifier = modifier.onFocusChanged { focused = it.isFocused }, enabled = enabled,
        scale = TvIconDefaults.scale(focusedScale = 1.15f),
        // White behind a focused icon, as the bar's pills; its content colour turns dark with it.
        colors = TvIconDefaults.colors(containerColor = Color.Transparent, contentColor = Palette.textPrimary,
            focusedContainerColor = Palette.textPrimary, focusedContentColor = Palette.canvas),
    ) { TvColour { androidx.compose.runtime.CompositionLocalProvider(LocalPillFocused provides focused) {
        androidx.compose.foundation.layout.Box(content = content) } } }
}

/** Focus styling for anything else clickable — rows, letters, cards — via Compose for TV's Surface look. */
val tvSurfaceScale = ClickableSurfaceDefaults.scale(focusedScale = 1.06f)
