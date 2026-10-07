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
 * own luminance, a shade darker and faintly cool. The gold goes grey with the
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
 * later): the accent follows the phone's own colours instead of the Mac's gold.
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
    // On a TV, Apple TV's greys: one even ground, cards a step lighter.
    val canvas get() = RoomTheme.map(if (TvLook.on) 0xFF1C1C1E else 0xFF0D0F12)
    val chrome get() = RoomTheme.map(if (TvLook.on) 0xFF242426 else 0xFF14171C)
    val surface get() = RoomTheme.map(if (TvLook.on) 0xFF2C2C2E else 0xFF1A1F26)
    val surfaceRaised get() = RoomTheme.map(if (TvLook.on) 0xFF3A3A3C else 0xFF22262D)
    val border get() = RoomTheme.map(0xFF262B33)
    val textPrimary get() = RoomTheme.map(0xFFF2F4F7)
    val textSecondary get() = RoomTheme.map(0xFFA8B0BC)
    val textMuted get() = RoomTheme.map(0xFF6B7381)
    val accent get() = MaterialYou.accent?.takeIf { !RoomTheme.isOn } ?: RoomTheme.map(if (Night.on) 0xFFA8823A else 0xFFC9A227)
    val onAccent get() = RoomTheme.map(0xFF0D0F12)
}

/** Phone or TV: decides card sizes, gutters and how focus is drawn. */
data class FormFactor(val isTv: Boolean) {
    val gutter get() = if (isTv) 48 else 16
    val posterWidth get() = if (isTv) 150 else 112
    val wideWidth get() = if (isTv) 280 else 220
}

val LocalFormFactor = staticCompositionLocalOf { FormFactor(isTv = false) }

fun detectFormFactor(context: Context): FormFactor {
    val ui = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
    // A Quest takes the TV layout: big targets, and focus the controller ray can move.
    return FormFactor(app.lumiere.android.AppBuild.quest || ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
}

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

/** After 10 pm the gold goes a softer amber, kinder to a dark room; set by the activity each hour. */
object Night {
    var on by androidx.compose.runtime.mutableStateOf(false)
}

/** Apple TV's grey ground on a TV; set by the activity. */
object TvLook {
    var on by androidx.compose.runtime.mutableStateOf(false)
}
