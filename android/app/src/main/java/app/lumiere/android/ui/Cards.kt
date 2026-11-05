package app.lumiere.android.ui

import androidx.compose.ui.graphics.drawscope.scale

import androidx.compose.ui.graphics.drawscope.translate

import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.zIndex
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.lumiere.android.api.Item
import app.lumiere.android.api.Server
import coil.compose.AsyncImage

private val cardShape = RoundedCornerShape(10.dp)

/**
 * Clickable, and visibly focused for a remote: a TV has no pointer, so the
 * focused card grows a little and takes the accent ring — the only way to
 * see where the d-pad is.
 */
@Composable
fun Modifier.focusCard(onClick: () -> Unit): Modifier = focusCard({}, onClick)

/** As above, also told when the remote arrives — TV Home changes its picture. */
@Composable
fun Modifier.focusCard(onFocused: () -> Unit, onClick: () -> Unit): Modifier = focusCard(onFocused, onClick, null)

/** With [onMenu]: a long press of OK, or the remote's Menu button, opens the card's actions. */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun Modifier.focusCard(onFocused: () -> Unit, onClick: () -> Unit, onMenu: (() -> Unit)?): Modifier {
    var focused by remember { mutableStateOf(false) }
    val tv = LocalFormFactor.current.isTv
    // tvOS's focus: quick, with a little bounce (about 0.15 s).
    // Up with a little bounce; down a beat later and gently, as Apple's cards settle.
    val lift by animateFloatAsState(if (focused) 1f else 0f,
        if (focused) androidx.compose.animation.core.spring(dampingRatio = 0.62f, stiffness = 900f)
        else androidx.compose.animation.core.tween(220, delayMillis = 60), label = "focus")
    // A light passing across the card as it is chosen, once.
    val shine = remember { androidx.compose.animation.core.Animatable(-1f) }
    LaunchedEffect(focused) {
        if (focused && tv && !app.lumiere.android.Motion.reduced && !app.lumiere.android.Device.lowMemory) { shine.snapTo(-0.4f); shine.animateTo(1.4f, androidx.compose.animation.core.tween(700)) }
    }
    val density = androidx.compose.ui.platform.LocalDensity.current
    // On the Quest the card follows the pointer, as Meta's TV app's posters do: tipped toward
    // where you point, lit where you point. It moves only with your hand, so Reduce Motion keeps it.
    val quest = app.lumiere.android.Flavor.quest
    var aim by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val me = remember { androidx.compose.ui.focus.FocusRequester() }
    val aimX by animateFloatAsState(aim.x, androidx.compose.animation.core.spring(stiffness = 260f), label = "aimX")
    val aimY by animateFloatAsState(aim.y, androidx.compose.animation.core.spring(stiffness = 260f), label = "aimY")
    val base = this
        .then(if (quest) Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    val e = awaitPointerEvent()
                    val p = e.changes.firstOrNull()?.position ?: continue
                    // Pointing at a card chooses it, as the remote arriving would.
                    if (e.type == androidx.compose.ui.input.pointer.PointerEventType.Enter) runCatching { me.requestFocus() }
                    aim = if (e.type == androidx.compose.ui.input.pointer.PointerEventType.Exit) androidx.compose.ui.geometry.Offset.Zero
                        else CardTilt.aim(p.x, p.y, size.width.toFloat(), size.height.toFloat())
                }
            }
        } else Modifier)
        .zIndex(if (focused) 1f else 0f)
        .then(if (!tv) Modifier.scale(1f + 0.06f * lift) else Modifier.graphicsLayer {
            // Raised, and tipped a few degrees toward the way the remote moved.
            // Further out on the Quest, where depth is the point: higher, and its shadow deeper and wider.
            val s = 1f + (if (quest) 0.13f else 0.1f) * lift
            scaleX = s; scaleY = s
            // The tilt only where there is power to spare; the projector keeps the lift alone.
            if (quest) {
                rotationY = aimX * CardTilt.DEGREES * lift
                rotationX = -aimY * CardTilt.DEGREES * lift
            } else if (!app.lumiere.android.Motion.reduced && !app.lumiere.android.Device.lowMemory) {
                rotationY = FocusDirection.dx * 5f * lift
                rotationX = -FocusDirection.dy * 4f * lift
            }
            cameraDistance = 14f * density.density
            shadowElevation = with(density) { (if (quest) 36.dp else 22.dp).toPx() } * lift
            if (quest) { ambientShadowColor = Color.Black; spotShadowColor = Color.Black }
            shape = cardShape; clip = false
        })
        .onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocused() }
        .clip(cardShape)
        .then(if (tv) Modifier.drawWithContent {
            // On the Quest the picture sits a little deeper than the card's frame and slides
            // against the tilt, so a lifted card reads as a window onto its scene.
            if (quest && lift > 0.01f) {
                val k = 1f + 0.06f * lift
                translate(-aimX * size.width * 0.03f * lift, -aimY * size.height * 0.03f * lift) { scale(k) { this@drawWithContent.drawContent() } }
            } else drawContent()
            // The Quest's light, where the pointer is on the card.
            if (quest && lift > 0.01f) drawRect(androidx.compose.ui.graphics.Brush.radialGradient(
                listOf(Color.White.copy(alpha = 0.2f * lift), Color.Transparent),
                center = androidx.compose.ui.geometry.Offset((aimX + 1) / 2 * size.width, (aimY + 1) / 2 * size.height),
                radius = size.maxDimension * 0.7f))
            if (focused && shine.value in -0.4f..1.4f) {
                val x = size.width * shine.value
                drawRect(androidx.compose.ui.graphics.Brush.linearGradient(
                    listOf(Color.Transparent, Color.White.copy(alpha = 0.22f), Color.Transparent),
                    start = androidx.compose.ui.geometry.Offset(x - size.width * 0.3f, 0f),
                    end = androidx.compose.ui.geometry.Offset(x + size.width * 0.3f, size.height)))
            }
        } else Modifier)
        .border(if (tv) 2.dp else 2.dp, if (focused) (if (tv) Color.White.copy(alpha = 0.9f) else Palette.accent) else Color.Transparent, cardShape)
    // Holding OK on a remote arrives as repeated key-downs, which clickable
    // never turns into a long click; the press is read here instead: a held
    // OK opens the menu, a short one clicks on release.
    var held by remember { mutableStateOf(false) }
    val menu = onMenu?.let { m -> { MenuReturn.to = me; m() } }
    return base.then(androidx.compose.ui.Modifier.focusRequester(me)).then(if (onMenu == null) Modifier.clickable(onClick = onClick) else Modifier
        .onPreviewKeyEvent { e ->
            val k = e.nativeKeyEvent
            val ok = k.keyCode == android.view.KeyEvent.KEYCODE_DPAD_CENTER || k.keyCode == android.view.KeyEvent.KEYCODE_ENTER ||
                k.keyCode == android.view.KeyEvent.KEYCODE_NUMPAD_ENTER
            when {
                k.keyCode == android.view.KeyEvent.KEYCODE_MENU && k.action == android.view.KeyEvent.ACTION_UP -> { menu!!(); true }
                ok && k.action == android.view.KeyEvent.ACTION_DOWN -> {
                    if (k.repeatCount == 0) held = false
                    else if (!held && (k.isLongPress || k.repeatCount >= 1)) { held = true; menu!!() }
                    true
                }
                ok && k.action == android.view.KeyEvent.ACTION_UP -> { if (!held) onClick(); held = false; true }
                else -> false
            }
        }
        .combinedClickable(onClick = onClick, onLongClick = menu))
}

/** The way the remote last moved, for the focused card's tilt. */
object FocusDirection {
    var dx = 0f
    var dy = 0f
}

/**
 * A card's actions on a long press or Menu: set by the activity on a TV, so
 * every poster anywhere offers them; null on a phone, which has its own.
 */
val LocalCardMenu = androidx.compose.runtime.staticCompositionLocalOf<((Item) -> Unit)?> { null }

/** Portrait for films and shows, wide for episodes and what is in progress. */
enum class CardShape { Poster, Wide }

@Composable
fun ItemCard(item: Item, server: Server, shape: CardShape, onFocus: (Item) -> Unit = {}, fill: Boolean = false, badge: String? = null, onClick: () -> Unit) {
    val form = LocalFormFactor.current
    val width = if (shape == CardShape.Poster) form.posterWidth else form.wideWidth
    Column(if (fill) Modifier.fillMaxWidth() else Modifier.width(width.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(if (shape == CardShape.Poster) 2f / 3f else 16f / 9f)
                // A phone's card sinks under the finger, as iOS's do.
                .then(if (form.isTv) Modifier else Modifier.pressScale())
                .focusCard({ onFocus(item) }, onClick, LocalCardMenu.current?.let { menu -> { menu(item) } })
                .background(Palette.surface)
        ) {
            AsyncImage(
                model = imageFor(item, server, shape, width * 2),
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize()
                    .then(if (RoomTheme.isOn && RoomTheme.blursCovers) Modifier.blur(18.dp) else Modifier),
            )
            // Blur is drawn only from Android 12; older screens get a veil instead.
            if (RoomTheme.isOn && RoomTheme.blursCovers && android.os.Build.VERSION.SDK_INT < 31) {
                Box(Modifier.matchParentSize().background(Palette.surface.copy(alpha = 0.92f)))
            }
            // On the Quest, 180°, 360° and 3D titles carry their tag, as Meta's TV app's do.
            (badge ?: if (app.lumiere.android.Flavor.quest) ImmersiveTag.of(item.name) else null)?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = Color.White,
                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp)) }
            item.progress?.let { fraction ->
                Box(
                    Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp)
                        .background(Color.Black.copy(alpha = 0.5f))
                ) {
                    Box(Modifier.fillMaxWidth(fraction).height(4.dp).background(Palette.accent, RoundedCornerShape(topEnd = 2.dp, bottomEnd = 2.dp)))
                }
            }
            WatchedMark(item, Modifier.align(Alignment.TopEnd))
            app.lumiere.android.ui.PendingMark(item.id, Modifier.align(Alignment.TopStart).padding(6.dp))
        }
        Spacer(Modifier.height(6.dp))
        Text(
            if (item.isEpisode) item.seriesName ?: item.name else item.name,
            style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
        val sub = if (item.isEpisode) listOfNotNull(item.episodeLabel, item.name).joinToString(" · ")
        else item.year?.toString() ?: ""
        Text(sub, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The picture a card shows: an episode's own still, else its show's art. */
fun imageFor(item: Item, server: Server, shape: CardShape, width: Int): String? = when {
    shape == CardShape.Poster && item.isEpisode && item.seriesId != null ->
        server.imageUrl(item.seriesId, "Primary", item.seriesPrimaryTag, width)
    shape == CardShape.Poster -> item.primaryTag?.let { server.imageUrl(item.id, "Primary", it, width) }
    item.isEpisode || item.type == "Video" -> item.primaryTag?.let { server.imageUrl(item.id, "Primary", it, width) }
        ?: item.parentBackdropId?.let { server.imageUrl(it, "Backdrop", item.parentBackdropTag, width) }
    else -> item.backdropTag?.let { server.imageUrl(item.id, "Backdrop", it, width) }
        ?: item.thumbTag?.let { server.imageUrl(item.id, "Thumb", it, width) }
        ?: item.primaryTag?.let { server.imageUrl(item.id, "Primary", it, width) }
}

/** One titled row of cards; drawn only when it has something in it. */
@Composable
fun Shelf(title: String, items: List<Item>, server: Server, shape: CardShape, onFocus: (Item) -> Unit = {},
          onOpen: (Item) -> Unit) {
    if (items.isEmpty()) return
    val form = LocalFormFactor.current
    Column(Modifier.padding(vertical = 10.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = form.gutter.dp))
        Spacer(Modifier.height(10.dp))
        LazyRow(
            contentPadding = PaddingValues(horizontal = form.gutter.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(if (form.isTv) 20.dp else 12.dp),
        ) {
            items(items, key = { it.id }) { item -> ItemCard(item, server, shape, onFocus) { onOpen(item) } }
        }
    }
}

/**
 * Watched, at a glance, on every card: an accent tick on a finished film, episode
 * or show; on a show not finished, how many episodes are unwatched, as the
 * Apple TV app marks them.
 */
@Composable
fun WatchedMark(item: Item, modifier: Modifier = Modifier) {
    val left = item.unplayedCount
    // A show's ChildCount is its seasons, not its episodes, so the count stands alone.
    val started = item.isSeries && !item.played && left != null && left > 0
    when {
        item.played -> Mark(Symbols.check, modifier.padding(6.dp).background(Palette.accent, RoundedCornerShape(50)).padding(4.dp),
            12.dp, tint = Palette.onAccent)
        started -> Text("$left", color = Color.White, style = MaterialTheme.typography.labelMedium,
            modifier = modifier.padding(6.dp).background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(50)).padding(horizontal = 7.dp))
    }
}

/** The card whose menu is open, for the remote to return to when it closes. */
object MenuReturn {
    var to: androidx.compose.ui.focus.FocusRequester? = null
}
