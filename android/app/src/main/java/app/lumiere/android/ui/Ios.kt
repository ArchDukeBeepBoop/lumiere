package app.lumiere.android.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/*
 * The phone's look, after the Apple TV app on an iPhone: large bold titles,
 * white capsule buttons, frosted round ones, rows that answer a touch by
 * sinking a little, grouped lists, and small capitals over a card's name.
 */

/** iOS's type: tight, heavy titles; quiet captions. */
object IosType {
    val largeTitle = TextStyle(fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp)
    val title = TextStyle(fontSize = 21.sp, lineHeight = 26.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp)
    val headline = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp)
    val body = TextStyle(fontSize = 15.sp, lineHeight = 21.sp)
    val caption = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 17.sp)
}

/**
 * Sinks a little under the finger and springs back, as iOS's cards and
 * buttons do. Only watches the touch: taps, long presses and scrolling still
 * go to whatever handles them.
 */
fun Modifier.pressScale(pressed: Float = 0.96f): Modifier = composed {
    var down by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (down) pressed else 1f,
        spring(dampingRatio = 0.55f, stiffness = if (down) 1400f else 500f), label = "press")
    this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .pointerInput(Unit) {
            awaitEachGesture {
                val first = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                down = true
                while (true) {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    val change = event.changes.firstOrNull { it.id == first.id } ?: break
                    // A finger that moves is scrolling, not pressing.
                    if ((change.position - first.position).getDistance() > viewConfiguration.touchSlop) down = false
                    if (!change.pressed) break
                }
                down = false
            }
        }
}

/** Clickable with the press and a light tick, no ripple — iOS has none. */
fun Modifier.iosClick(onClick: () -> Unit): Modifier = composed {
    val haptic = LocalHapticFeedback.current
    this.pressScale().clickable(remember { MutableInteractionSource() }, indication = null) {
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); onClick()
    }
}

/**
 * Apple's capsule button: white with dark words for the main action, a
 * frosted grey for the others.
 */
@Composable
fun IosButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null,
              primary: Boolean = true, enabled: Boolean = true) {
    val fg = if (primary) Color.Black else Color.White
    Row(modifier.height(48.dp).clip(RoundedCornerShape(12.dp))
        .background(if (primary) Color.White.copy(alpha = if (enabled) 1f else 0.5f) else Color.White.copy(alpha = 0.16f))
        .then(if (enabled) Modifier.iosClick(onClick) else Modifier).padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        icon?.let { Icon(it, null, tint = fg, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(6.dp)) }
        Text(text, style = IosType.headline, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A frosted circle with an icon: "+", "…", the remote, the back chevron over artwork. */
@Composable
fun IosCircle(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, size: Int = 44,
              tint: Color = Color.White, filled: Boolean = false) {
    Box(modifier.size(size.dp).clip(CircleShape)
        .background(if (filled) Color.White else Color.White.copy(alpha = 0.16f))
        .iosClick(onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = if (filled) Color.Black else tint, modifier = Modifier.size((size * 0.5f).dp))
    }
}

/** A row's title in Apple's weight, with a chevron when it opens the whole row. */
@Composable
fun IosSectionHeader(title: String, modifier: Modifier = Modifier, subtitle: String? = null, onMore: (() -> Unit)? = null) {
    Column(modifier.fillMaxWidth().then(if (onMore != null) Modifier.clickable(remember { MutableInteractionSource() }, null, onClick = onMore) else Modifier)
        .padding(horizontal = LocalFormFactor.current.gutter.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = IosType.title, color = Palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false))
            if (onMore != null) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "See all", tint = Palette.textSecondary,
                modifier = Modifier.size(26.dp))
        }
        subtitle?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary) }
    }
}

/** Small capitals above a card's name: RESUME, NEXT EPISODE, UP NEXT. */
@Composable
fun IosCaption(text: String, modifier: Modifier = Modifier, color: Color = Palette.textSecondary) {
    Text(text.uppercase(), style = IosType.caption, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = modifier)
}

/** A screen's large title, with its buttons on the right. */
@Composable
fun IosLargeTitle(title: String, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(modifier.fillMaxWidth().padding(start = 16.dp, end = 12.dp, top = 8.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosType.largeTitle, color = Palette.textPrimary, modifier = Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, content = trailing)
    }
}

/**
 * The bar that settles over the top as a page scrolls: clear over artwork,
 * then near-black with the page's name, as iOS's navigation bar does.
 * [shown] from 0 (clear) to 1.
 */
@Composable
fun IosTopBar(shown: Float, title: String, modifier: Modifier = Modifier, underStatusBar: Boolean = true,
              leading: @Composable RowScope.() -> Unit = {}, trailing: @Composable RowScope.() -> Unit = {}) {
    Box(modifier.fillMaxWidth().background(Palette.canvas.copy(alpha = 0.97f * shown))) {
        Row(Modifier.fillMaxWidth().then(if (underStatusBar) Modifier.statusBarsPadding() else Modifier).height(if (underStatusBar) 52.dp else 44.dp)
            .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, content = leading)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, content = trailing)
        }
        Text(title, style = IosType.headline, color = Palette.textPrimary.copy(alpha = shown), maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = if (underStatusBar) 15.dp else 12.dp, start = 96.dp, end = 96.dp))
        if (shown > 0.5f) HorizontalDivider(Modifier.align(Alignment.BottomCenter), 0.5.dp, Color.White.copy(alpha = 0.12f * shown))
    }
}

/** One row of a grouped list: a coloured tile, a name, a value, a chevron. */
data class IosRow(
    val title: String,
    val icon: ImageVector? = null,
    val tile: Color = Color(0xFF3A3A3C),
    val value: String? = null,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/** iOS's inset grouped list: rounded together, hairlines between. */
@Composable
fun IosGroup(rows: List<IosRow>, modifier: Modifier = Modifier, header: String? = null, footer: String? = null) {
    if (rows.isEmpty()) return
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        header?.let { IosCaption(it, Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Palette.surface)) {
            rows.forEachIndexed { i, r ->
                Row(Modifier.fillMaxWidth().clickable(onClick = r.onClick).padding(horizontal = 14.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    r.icon?.let {
                        Box(Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)).background(r.tile), contentAlignment = Alignment.Center) {
                            Icon(it, null, tint = Color.White, modifier = Modifier.size(19.dp))
                        }
                        Spacer(Modifier.width(12.dp))
                    }
                    Text(r.title, style = IosType.body, color = if (r.destructive) Color(0xFFFF453A) else Palette.textPrimary,
                        modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    r.value?.let { Text(it, style = IosType.body, color = Palette.textSecondary, maxLines = 1) }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Palette.textMuted, modifier = Modifier.size(22.dp))
                }
                if (i < rows.lastIndex) HorizontalDivider(Modifier.padding(start = if (r.icon != null) 56.dp else 14.dp),
                    0.5.dp, Palette.border)
            }
        }
        footer?.let { Text(it, style = IosType.footnote, color = Palette.textSecondary, modifier = Modifier.padding(start = 16.dp, top = 6.dp, end = 16.dp)) }
    }
}

/** The account's initial in a circle, top right, as Apple puts the account there; opens Settings. */
@Composable
fun IosAvatar(name: String, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape)
        .background(androidx.compose.ui.graphics.Brush.linearGradient(listOf(Color(0xFF8E8E93), Color(0xFF48484A))))
        .iosClick(onClick), contentAlignment = Alignment.Center) {
        Text(name.trim().firstOrNull()?.uppercase() ?: "•", style = IosType.headline, color = Color.White)
    }
}

/** iOS's capsule filter: white with dark words when chosen, grey otherwise. */
@Composable
fun IosChip(selected: Boolean, label: String, onClick: () -> Unit) {
    Text(label, style = IosType.footnote.copy(fontWeight = FontWeight.SemiBold), color = if (selected) Color.Black else Palette.textPrimary,
        maxLines = 1, modifier = Modifier.clip(RoundedCornerShape(50)).background(if (selected) Color.White else Palette.surface)
            .iosClick(onClick).padding(horizontal = 14.dp, vertical = 7.dp))
}

/** iOS's rounded search field, the magnifier and placeholder inside, a clear button once typed in. */
@Composable
fun IosSearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(38.dp).clip(RoundedCornerShape(10.dp)).background(Palette.surface).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(androidx.compose.material.icons.Icons.Default.Search, null, tint = Palette.textSecondary, modifier = Modifier.size(19.dp))
        Spacer(Modifier.width(6.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = IosType.body, color = Palette.textMuted, maxLines = 1)
            androidx.compose.foundation.text.BasicTextField(value, onChange, singleLine = true,
                textStyle = IosType.body.copy(color = Palette.textPrimary),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(Palette.accent), modifier = Modifier.fillMaxWidth())
        }
        if (value.isNotEmpty()) Icon(androidx.compose.material.icons.Icons.Default.Cancel, "Clear", tint = Palette.textMuted,
            modifier = Modifier.size(19.dp).clickable { onChange("") })
    }
}

/**
 * The small title iOS shows once a page's large title has scrolled away:
 * put over a page whose first item is its [IosLargeTitle].
 */
@Composable
fun IosCollapsedTitle(list: androidx.compose.foundation.lazy.LazyListState, title: String) {
    val shown by androidx.compose.runtime.remember { androidx.compose.runtime.derivedStateOf {
        if (list.firstVisibleItemIndex > 0) 1f else (list.firstVisibleItemScrollOffset / 90f).coerceIn(0f, 1f)
    } }
    if (shown > 0f) IosTopBar(shown, title, underStatusBar = false)
}

/** As [IosCollapsedTitle], for a grid. */
@Composable
fun IosCollapsedTitle(grid: androidx.compose.foundation.lazy.grid.LazyGridState, title: String, threshold: Int = 0) {
    val shown by androidx.compose.runtime.remember { androidx.compose.runtime.derivedStateOf {
        if (grid.firstVisibleItemIndex > threshold) 1f else (grid.firstVisibleItemScrollOffset / 90f).coerceIn(0f, 1f) * (if (threshold == 0) 1f else 0f)
    } }
    if (shown > 0f) IosTopBar(shown, title, underStatusBar = false)
}

/** Posters across a phone grid: three, as iOS; more in a wide window — the Quest's, or a phone on its side. */
@Composable
fun phoneColumns(): Int {
    val w = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp
    return if (w < 600) 3 else (w / 150).coerceAtLeast(4)
}

/** A full-bleed picture's height: [ratio] of the width on a phone held upright, never more than most of a wide window. */
@Composable
fun heroHeight(ratio: Float): androidx.compose.ui.unit.Dp {
    val c = androidx.compose.ui.platform.LocalConfiguration.current
    return minOf(c.screenWidthDp / ratio, c.screenHeightDp * 0.78f).dp
}

/** iOS's segmented control: a grey track, the chosen segment raised in a lighter grey. */
@Composable
fun IosSegmented(options: List<String>, selected: Int, onPick: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(34.dp).clip(RoundedCornerShape(9.dp)).background(Palette.surface).padding(2.dp)) {
        options.forEachIndexed { i, o ->
            Box(Modifier.weight(1f).fillMaxWidth().height(30.dp).clip(RoundedCornerShape(7.dp))
                .background(if (i == selected) Color(0xFF636366) else Color.Transparent)
                .clickable(remember { MutableInteractionSource() }, null) { onPick(i) }, contentAlignment = Alignment.Center) {
                Text(o, style = IosType.footnote.copy(fontWeight = FontWeight.SemiBold), color = Palette.textPrimary, maxLines = 1)
            }
        }
    }
}

/** Apple Music's grey capsule with words in the accent: Play, Shuffle. */
@Composable
fun IosTintedButton(text: String, icon: ImageVector, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.height(46.dp).clip(RoundedCornerShape(12.dp)).background(Palette.surface).iosClick(onClick),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Palette.accent, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, style = IosType.headline, color = Palette.accent)
    }
}
