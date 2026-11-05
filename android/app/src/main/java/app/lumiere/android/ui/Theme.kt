package app.lumiere.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * The private room's palette, as on the Mac: every colour passed through its
 * own luminance, a shade darker and faintly cool. The accent goes grey with the
 * rest, so a glance tells which space is open.
 */
object RoomTheme {
    private val on = androidx.compose.runtime.mutableStateOf(false)
    var isOn: Boolean get() = on.value
        set(v) { on.value = v }
    private val blur = androidx.compose.runtime.mutableStateOf(false)
    /** Covers blurred in lists while the room is open. */
    var blursCovers: Boolean get() = blur.value
        set(v) { blur.value = v }

    fun map(argb: Long): Color {
        if (!isOn) return Color(argb)
        val r = (argb shr 16 and 0xFF).toDouble(); val g = (argb shr 8 and 0xFF).toDouble(); val b = (argb and 0xFF).toDouble()
        val y = (0.2126 * r + 0.7152 * g + 0.0722 * b) * 0.88
        fun c(v: Double) = v.coerceIn(0.0, 255.0).toInt()
        return Color(c(y - 2), c(y), c(y + 6))
    }
}

/**
 * On a phone, with Settings' "Colours from my wallpaper" on (Android 12 and
 * later): the accent follows the phone's own colours instead of the prism's periwinkle.
 * The private room keeps its own look.
 */
object MaterialYou {
    var accent by androidx.compose.runtime.mutableStateOf<Color?>(null)

    fun follow(context: Context, on: Boolean, isTv: Boolean) {
        accent = if (on && !isTv && android.os.Build.VERSION.SDK_INT >= 31)
            Color(context.getColor(android.R.color.system_accent1_200)) else null
    }
}

/** The Mac app's dark palette (Theme.Palette), carried over value for value. */
object Palette {
    // The prism icon's midnight, as on the Mac: navy greys rather than black.
    // On a TV, one even ground, cards a step lighter. On a phone, the deepest
    // navy (all but black, for an OLED) with grouped surfaces above it.
    val canvas get() = RoomTheme.map(if (TvLook.on) 0xFF13162A else if (PhoneLook.on) 0xFF0B0D1C else 0xFF13162A)
    val chrome get() = RoomTheme.map(if (TvLook.on) 0xFF191C33 else if (PhoneLook.on) 0xFF111428 else 0xFF191C33)
    val surface get() = RoomTheme.map(if (TvLook.on) 0xFF21253F else if (PhoneLook.on) 0xFF191C33 else 0xFF21253F)
    val surfaceRaised get() = RoomTheme.map(if (TvLook.on) 0xFF2D3150 else if (PhoneLook.on) 0xFF262A47 else 0xFF2D3150)
    val border get() = RoomTheme.map(if (PhoneLook.on) 0xFF343957 else 0xFF2A2E4A)
    val textPrimary get() = RoomTheme.map(if (PhoneLook.on) 0xFFFFFFFF else 0xFFF3F4FA)
    val textSecondary get() = RoomTheme.map(if (PhoneLook.on) 0xFFA6A9C2 else 0xFFADB0C6)
    val textMuted get() = RoomTheme.map(if (PhoneLook.on) 0xFF71758F else 0xFF7A7E9A)
    /** The icon's edge light, #9296FF; a softer periwinkle after 10 pm. */
    val accent get() = MaterialYou.accent?.takeIf { !RoomTheme.isOn } ?: RoomTheme.map(if (Night.on) 0xFF7A7FD6 else 0xFF9296FF)
    val onAccent get() = RoomTheme.map(0xFF13162A)
    /**
     * A page's own ground: the canvas, but clear in the Quest's window, where every page
     * sits on the one colour ground behind it (QuestBackdrop), as Horizon OS's panels do.
     */
    val ground get() = if (app.lumiere.android.Flavor.quest) androidx.compose.ui.graphics.Color.Transparent else canvas
}

/** Phone or TV: decides card sizes, gutters and how focus is drawn. */
data class FormFactor(val isTv: Boolean) {
    val gutter get() = if (isTv) 48 else 16
    val posterWidth get() = if (isTv) 150 else 112
    val wideWidth get() = if (isTv) 280 else 220
}

val LocalFormFactor = staticCompositionLocalOf { FormFactor(isTv = false) }

/**
 * The TV's layout in the TV's app, the touch layout in the phone's and the
 * Quest's — by which app this is (Flavor), not by guessing from the device:
 * a headset once passed for a TV.
 */
@Suppress("UNUSED_PARAMETER")
// The Quest's window takes the TV layout too: big targets, and a focus its controllers move.
fun detectFormFactor(context: Context): FormFactor = FormFactor(isTv = app.lumiere.android.Flavor.tv || app.lumiere.android.Flavor.quest)

@Composable
fun LumiereTheme(content: @Composable () -> Unit) {
    val colors = darkColorScheme(
        background = Palette.canvas, surface = Palette.surface, primary = Palette.accent,
        onPrimary = Palette.onAccent, onBackground = Palette.textPrimary, onSurface = Palette.textPrimary,
        surfaceVariant = Palette.surfaceRaised, onSurfaceVariant = Palette.textSecondary,
        outline = Palette.border,
    )
    val type = Typography(
        headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
        titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
        titleMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
        bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, color = Palette.textSecondary),
        labelMedium = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
    )
    MaterialTheme(colorScheme = colors, typography = type, content = content)
}

/** After 10 pm the accent goes a softer periwinkle, kinder to a dark room; set by the activity each hour. */
object Night {
    var on by androidx.compose.runtime.mutableStateOf(false)
}

/** The phone's deeper navy; set by the activity. */
object PhoneLook {
    var on by androidx.compose.runtime.mutableStateOf(false)
}

/** The TV's even navy ground; set by the activity. */
object TvLook {
    var on by androidx.compose.runtime.mutableStateOf(false)
}
