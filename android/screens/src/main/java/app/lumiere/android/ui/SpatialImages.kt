package app.lumiere.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import app.lumiere.android.OpenApp

/**
 * [content] with the window's signed-in image loader, for a panel of its
 * own (the Quest's poster wall, ornament, transport). Without it, a panel
 * asks for posters with no sign-in and draws them blank.
 */
@Composable
fun WithAppImages(content: @Composable () -> Unit) {
    val images = OpenApp.images
    @Suppress("DEPRECATION")
    if (images == null) content() else CompositionLocalProvider(coil.compose.LocalImageLoader provides images, content = content)
}
