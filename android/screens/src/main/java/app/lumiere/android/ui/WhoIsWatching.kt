@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.lumiere.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.AppState
import app.lumiere.android.Profile
import app.lumiere.android.Profiles
import app.lumiere.android.api.PublicUser
import app.lumiere.android.api.Server
import app.lumiere.android.api.myImageTag
import app.lumiere.android.api.publicUsers
import app.lumiere.android.api.userImageUrl
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What a profile with no picture wears behind its initial: muted, as Apple TV's monograms are. */
private val avatarColours = listOf(0xFF5B7FD6, 0xFFD06A55, 0xFF4E9F86, 0xFF9C76CF, 0xFFC4923A, 0xFF4F97B8)

/**
 * "Who's watching?", as Netflix and the Apple TV app open: everyone signed in
 * on this device as round pictures in a row, their names under them, and Add
 * Profile at the end. The remote moves along the row and OK chooses; on a
 * Quest you point, and a pinch chooses. Edit marks each one for removal from
 * this device. While it's up it stands in for every screen (MainActivity), so
 * nothing of whoever was watching shows behind it.
 */
@Composable
fun WhoIsWatching(state: AppState) {
    val tv = LocalFormFactor.current.isTv
    var adding by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<Profile?>(null) }
    LaunchedEffect(Unit) { refreshPictures(state) }
    if (adding) { AddProfile(state) { adding = false }; return }

    val profiles = state.profiles
    val here = state.currentProfile?.key?.takeIf { k -> profiles.any { it.key == k } } ?: profiles.firstOrNull()?.key
    val first = remember { FocusRequester() }
    val addTile = remember { FocusRequester() }
    val keep = remember { FocusRequester() }
    BackHandler {
        when {
            removing != null -> removing = null
            editing -> editing = false
            state.choosingCanCancel -> state.keepWatching()
            else -> state.confirmExit = true
        }
    }
    // The remote lands on whoever watched last, or on Keep while a removal is asked; again once one is
    // gone, and once something over the faces closes (Leave Lumiere?, what stopped the app last time).
    val covered = state.confirmExit || state.crashReport != null
    LaunchedEffect(editing, removing, profiles.size, covered) {
        if (covered) return@LaunchedEffect
        delay(60)
        runCatching { (if (removing != null) keep else first).requestFocus() }
    }
    val size = if (tv) 120.dp else 92.dp
    Box(Modifier.fillMaxSize().background(Palette.canvas).systemBarsPadding(), contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Text(if (editing) "Remove a Profile" else "Who’s watching?", textAlign = TextAlign.Center,
                style = TextStyle(fontSize = if (tv) 38.sp else 30.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
            if (editing) Text("A profile removed here is signed out of this device only; it stays on the server.",
                style = MaterialTheme.typography.bodyMedium, color = Palette.textSecondary, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 10.dp))
            FlowRow(Modifier.padding(top = if (tv) 40.dp else 28.dp),
                horizontalArrangement = Arrangement.spacedBy(if (tv) 20.dp else 8.dp, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                profiles.forEach { p ->
                    key(p.key) {
                        val mine = remember { FocusRequester() }
                        AvatarTile(p.name, size, if (p.key == here) first else mine, badge = editing,
                            onClick = { if (editing) removing = p else state.choose(p) }) { ProfileAvatar(p, size) }
                    }
                }
                if (!editing) AvatarTile("Add Profile", size, if (here == null) first else addTile, onClick = { adding = true }) {
                    PlainCircle(size, Icons.Default.Add)
                }
            }
            Spacer(Modifier.height(28.dp))
            val asking = removing
            if (asking == null) {
                LButton(primary = false, onClick = { editing = !editing }) { Text(if (editing) "Done" else "Edit") }
            } else {
                val watching = state.session?.let(Profiles::key) == asking.key
                Text(if (watching) "Remove ${asking.name}? They’ll be signed out of this device." else "Remove ${asking.name} from this device?",
                    style = MaterialTheme.typography.titleMedium, color = Palette.textPrimary, textAlign = TextAlign.Center)
                Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    LButton(onClick = { removing = null; state.removeProfile(asking.key) }) { Text("Remove") }
                    LButton(primary = false, onClick = { removing = null }, modifier = Modifier.focusRequester(keep)) { Text("Keep") }
                }
            }
        }
    }
}

/**
 * A new profile on the server of whoever is watching: the people it lists
 * (Users/Public) as round pictures, a password asked only of those who have
 * one, and Someone Else for anyone it keeps hidden. Lumiere's own server
 * lists nobody, so there the name and password come first. Another Server
 * is the sign-in screen itself. Signing in makes the new profile the one
 * watching; Back returns to the faces.
 */
@Composable
private fun AddProfile(state: AppState, back: () -> Unit) {
    val server = state.server ?: return
    val tv = LocalFormFactor.current.isTv
    val scope = rememberCoroutineScope()
    var users by remember { mutableStateOf<List<PublicUser>?>(null) }
    var who by remember { mutableStateOf<PublicUser?>(null) }
    var someoneElse by remember { mutableStateOf(false) }
    var elsewhere by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(server) {
        val saved = state.profiles.filter { it.session.serverUrl == server.baseUrl }.map { it.session.userId }.toSet()
        val listed = runCatching { server.publicUsers() }.getOrDefault(emptyList()).filter { it.id !in saved }
        users = listed
        if (listed.isEmpty()) someoneElse = true
    }
    if (elsewhere) {
        BackHandler { elsewhere = false }
        SignInScreen(state)
        return
    }
    val asking = who != null || (someoneElse && users.orEmpty().isNotEmpty())
    BackHandler { if (asking && !busy) { who = null; someoneElse = false; password = ""; message = null } else if (!busy) back() }

    fun signIn(user: String, tag: String?) {
        // Never a button that silently does nothing: say what's missing.
        signInProblem(user, password, "", needsAccount = false)?.let { (problem, _) -> message = problem; return }
        if (busy) return
        scope.launch {
            busy = true
            message = null
            val fresh = Server(server.baseUrl, state.deviceId)
            runCatching { fresh.signIn(user.trim(), password) }
                .onSuccess { state.signedIn(it, fresh, tag) }
                .onFailure { message = signInFailure(it, server.baseUrl) }
            busy = false
        }
    }

    val size = if (tv) 96.dp else 80.dp
    val px = with(LocalDensity.current) { size.roundToPx() }
    val firstTile = remember { FocusRequester() }
    val someoneTile = remember { FocusRequester() }
    val nameField = remember { FocusRequester() }
    val passwordField = remember { FocusRequester() }
    LaunchedEffect(who, someoneElse, users == null) {
        delay(60)
        runCatching {
            when {
                someoneElse -> nameField.requestFocus()
                who != null -> passwordField.requestFocus()
                users != null -> firstTile.requestFocus()
            }
        }
    }
    val serverName = state.session?.serverName ?: "this server"
    Box(Modifier.fillMaxSize().background(Palette.canvas).systemBarsPadding(), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Add a Profile", style = TextStyle(fontSize = if (tv) 34.sp else 28.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary))
            Text("Someone else who watches on $serverName, signed in on this device too.", style = MaterialTheme.typography.bodyMedium,
                color = Palette.textSecondary, textAlign = TextAlign.Center)
            val listed = users
            val chosen = who
            when {
                listed == null -> Text("Asking $serverName who watches there…", style = MaterialTheme.typography.bodyMedium, color = Palette.textMuted)
                chosen == null && !someoneElse -> FlowRow(horizontalArrangement = Arrangement.spacedBy(if (tv) 16.dp else 8.dp, Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    listed.forEachIndexed { i, u ->
                        key(u.id) {
                            val mine = remember { FocusRequester() }
                            AvatarTile(u.name, size, if (i == 0) firstTile else mine, onClick = {
                                who = u; password = ""; message = null
                                // Nobody's password to ask for: signed in at once.
                                if (!u.hasPassword) signIn(u.name, u.imageTag)
                            }) { Avatar(u.name, Profiles.key(server.baseUrl, u.id), u.imageTag?.let { userImageUrl(server.baseUrl, u.id, it, px) }, size) }
                        }
                    }
                    AvatarTile("Someone Else", size, if (listed.isEmpty()) firstTile else someoneTile,
                        onClick = { someoneElse = true; message = null }) { PlainCircle(size, Icons.Default.Person) }
                }
            }
            if (chosen != null || someoneElse) {
                chosen?.let { u ->
                    Avatar(u.name, Profiles.key(server.baseUrl, u.id), u.imageTag?.let { userImageUrl(server.baseUrl, u.id, it, px) }, 72.dp)
                    Text(u.name, style = MaterialTheme.typography.titleMedium, color = Palette.textPrimary)
                }
                if (someoneElse) OutlinedTextField(
                    value = name, onValueChange = { name = it }, label = { Text("User name") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    modifier = Modifier.fillMaxWidth().focusRequester(nameField).remoteLeavesField(),
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text(if (chosen != null) "Password for ${chosen.name}" else "Password") },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { signIn(chosen?.name ?: name, chosen?.imageTag) }),
                    modifier = Modifier.fillMaxWidth().focusRequester(passwordField).remoteLeavesField(),
                )
                message?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.background(Palette.surface, RoundedCornerShape(8.dp)).padding(12.dp))
                }
                LButton(onClick = { signIn(chosen?.name ?: name, chosen?.imageTag) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text(if (busy) "Signing in…" else "Sign In")
                }
            }
            LButton(primary = false, onClick = { elsewhere = true }, enabled = !busy) { Text("Another Server") }
        }
    }
}

/** Each picture as the server keeps it now: everyone it lists, and the one watching (Users/Me). */
private suspend fun refreshPictures(state: AppState) {
    val server = state.server ?: return
    val me = state.session ?: return
    val tags = mutableMapOf<String, String?>()
    runCatching { server.publicUsers() }.getOrNull()?.forEach { tags[Profiles.key(server.baseUrl, it.id)] = it.imageTag }
    runCatching { server.myImageTag() }.onSuccess { tags[Profiles.key(me)] = it }
    state.updateProfileImages(tags)
}

/**
 * One face on "Who's watching?": the picture lifts and takes a white ring
 * where the remote or your pointing is, as Apple TV's do, and the name under
 * it brightens. The whole tile is the target, name and all.
 */
@Composable
private fun AvatarTile(name: String, size: Dp, focus: FocusRequester, onClick: () -> Unit, badge: Boolean = false,
                       picture: @Composable () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    // Up with a little bounce, down a beat later and gently, as the cards do.
    val spec: androidx.compose.animation.core.AnimationSpec<Float> = when {
        app.lumiere.android.Motion.reduced -> snap()
        focused -> spring(dampingRatio = 0.62f, stiffness = 900f)
        else -> tween(220, delayMillis = 60)
    }
    val lift by animateFloatAsState(if (focused) 1f else 0f, spec, label = "avatar")
    Column(Modifier.width(size + 48.dp).onFocusChanged { focused = it.isFocused }.focusRequester(focus).hoverFocuses(focus)
        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
        .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.graphicsLayer { val s = 1f + 0.1f * lift; scaleX = s; scaleY = s }
            .border(3.dp, Color.White.copy(alpha = 0.95f * lift), CircleShape).padding(6.dp)) {
            picture()
            // Edit: each face marked for removal, as Netflix marks them for changing.
            if (badge) Box(Modifier.align(Alignment.TopEnd).size(size * 0.3f).background(Color(0xFFE5484D), CircleShape)
                .border(2.dp, Palette.canvas, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Remove, "Remove", tint = Color.White, modifier = Modifier.size(size * 0.2f))
            }
        }
        Text(name, style = MaterialTheme.typography.titleMedium, color = if (focused) Palette.textPrimary else Palette.textSecondary,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
    }
}

/**
 * A person's picture, round: the one their server keeps, over a coloured
 * circle with their initial, which is all that shows when there's none or
 * while it comes. Through whichever signed-in image loader is in scope.
 */
@Composable
fun ProfileAvatar(profile: Profile?, size: Dp, modifier: Modifier = Modifier) {
    if (profile == null) return
    val px = with(LocalDensity.current) { size.roundToPx() }
    val url = profile.imageTag?.let { userImageUrl(profile.session.serverUrl, profile.session.userId, it, px) }
    Avatar(profile.name, profile.key, url, size, modifier)
}

@Composable
private fun Avatar(name: String, key: String, url: String?, size: Dp, modifier: Modifier = Modifier) {
    val colour = Color(avatarColours[Profiles.tint(key, avatarColours.size)])
    val letter = with(LocalDensity.current) { (size * 0.42f).toSp() }
    Box(modifier.size(size).clip(CircleShape).background(Brush.linearGradient(listOf(colour, lerp(colour, Color.Black, 0.35f)))),
        contentAlignment = Alignment.Center) {
        Text(Profiles.initial(name), color = Color.White, fontSize = letter, fontWeight = FontWeight.SemiBold)
        if (url != null) AsyncImage(url, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    }
}

/** Add Profile's and Someone Else's circle: plain, with its sign. */
@Composable
private fun PlainCircle(size: Dp, icon: ImageVector) {
    Box(Modifier.size(size).clip(CircleShape).background(Palette.surfaceRaised), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Palette.textPrimary, modifier = Modifier.size(size * 0.4f))
    }
}

/** On a TV, the remote's up and down move on out of a text field, as from any row; left and right still move the cursor. */
@Composable
private fun Modifier.remoteLeavesField(): Modifier {
    if (!LocalFormFactor.current.isTv) return this
    val focus = LocalFocusManager.current
    return onPreviewKeyEvent { e ->
        if (e.nativeKeyEvent.action != android.view.KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
        when (e.nativeKeyEvent.keyCode) {
            android.view.KeyEvent.KEYCODE_DPAD_UP -> focus.moveFocus(FocusDirection.Up)
            android.view.KeyEvent.KEYCODE_DPAD_DOWN -> focus.moveFocus(FocusDirection.Down)
            else -> false
        }
    }
}

/**
 * The Quest tab bar's way to "Who's watching?": the picture of whoever is
 * watching, in the bar's round glass, brighter where you point. The bar is a
 * panel of its own, so the picture comes through the window's signed-in images.
 */
@Composable
fun ProfileGlassButton(profile: Profile?, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    Box(Modifier.size(52.dp).background(if (hovered) Color.White.copy(alpha = 0.22f) else Color.Transparent, CircleShape)
        .hoverable(source).clickable(interactionSource = source, indication = null, onClick = onClick)
        .semantics { contentDescription = "Who’s watching? ${profile?.name.orEmpty()}" },
        contentAlignment = Alignment.Center) {
        WithAppImages { ProfileAvatar(profile, 32.dp) }
    }
}
