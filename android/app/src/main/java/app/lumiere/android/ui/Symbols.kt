package app.lumiere.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size

/**
 * Lumiere's symbols, one family as Apple's SF Symbols are one: a 24-unit grid,
 * a 2-unit stroke with round caps and joins, solid shapes where a mark is "on".
 * Drawn in code, so they are sharp at any size and there is nothing to load or
 * decode. `Icon(..., tint = …)` colours them; the colour drawn here is ignored.
 * Sizes: 16 dp beside text, 20 dp in buttons, 28 dp in alerts (TV_PLAYER_PLAN §6).
 */
object Symbols {
    private fun symbol(name: String, block: ImageVector.Builder.() -> Unit): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply(block).build()

    /** A stroked line drawing. */
    private fun ImageVector.Builder.line(width: Float = 2f, draw: PathBuilder.() -> Unit) =
        path(stroke = SolidColor(Color.Black), strokeLineWidth = width, strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round, pathBuilder = draw)

    /** A solid shape, its corners softened by a thin stroke of the same colour. */
    private fun ImageVector.Builder.solid(soften: Float = 1.5f, draw: PathBuilder.() -> Unit) =
        path(fill = SolidColor(Color.Black), stroke = SolidColor(Color.Black), strokeLineWidth = soften,
            strokeLineJoin = StrokeJoin.Round, pathBuilder = draw)

    private fun PathBuilder.dot(x: Float, y: Float, r: Float) {
        moveTo(x - r, y); arcToRelative(r, r, 0f, true, true, 2 * r, 0f); arcToRelative(r, r, 0f, true, true, -2 * r, 0f); close()
    }

    private fun PathBuilder.roundRect(l: Float, t: Float, r: Float, b: Float, c: Float) {
        moveTo(l + c, t); lineTo(r - c, t); arcTo(c, c, 0f, false, true, r, t + c)
        lineTo(r, b - c); arcTo(c, c, 0f, false, true, r - c, b)
        lineTo(l + c, b); arcTo(c, c, 0f, false, true, l, b - c)
        lineTo(l, t + c); arcTo(c, c, 0f, false, true, l + c, t); close()
    }

    // Playback

    val play = symbol("play") { solid { moveTo(7.5f, 5f); lineTo(19f, 12f); lineTo(7.5f, 19f); close() } }
    val pause = symbol("pause") { line(3.6f) { moveTo(8.5f, 6f); lineTo(8.5f, 18f); moveTo(15.5f, 6f); lineTo(15.5f, 18f) } }
    val next = symbol("next") {
        solid { moveTo(5f, 5.5f); lineTo(15f, 12f); lineTo(5f, 18.5f); close() }
        line(2.6f) { moveTo(18.8f, 5.5f); lineTo(18.8f, 18.5f) }
    }
    val previous = symbol("previous") {
        solid { moveTo(19f, 5.5f); lineTo(9f, 12f); lineTo(19f, 18.5f); close() }
        line(2.6f) { moveTo(5.2f, 5.5f); lineTo(5.2f, 18.5f) }
    }
    /** A circular arrow turning back, open at the top, the mark beside "−10". */
    val skipBack = symbol("skipBack") {
        line { moveTo(12f, 5f); arcTo(8f, 8f, 0f, true, true, 4.8f, 9.6f) }
        line { moveTo(14.5f, 2.5f); lineTo(12f, 5f); lineTo(14.5f, 7.5f) }
    }
    /** The same, turning forward: the mark beside "+10". */
    val skipForward = symbol("skipForward") {
        line { moveTo(12f, 5f); arcTo(8f, 8f, 0f, true, false, 19.2f, 9.6f) }
        line { moveTo(9.5f, 2.5f); lineTo(12f, 5f); lineTo(9.5f, 7.5f) }
    }

    // The player's buttons and menus

    /** A speech bubble with lines of text: subtitles. */
    val subtitles = symbol("subtitles") {
        line { roundRect(3f, 5f, 21f, 17.5f, 3f) }
        line { moveTo(7f, 10f); lineTo(10.5f, 10f); moveTo(13.5f, 10f); lineTo(17f, 10f); moveTo(7f, 13.5f); lineTo(14.5f, 13.5f) }
        line { moveTo(8f, 17.5f); lineTo(7f, 20.5f); lineTo(11.5f, 17.5f) }
    }
    /** A waveform: audio. */
    val audio = symbol("audio") {
        line { moveTo(4f, 10.5f); lineTo(4f, 13.5f); moveTo(8f, 7.5f); lineTo(8f, 16.5f); moveTo(12f, 4f); lineTo(12f, 20f)
            moveTo(16f, 8f); lineTo(16f, 16f); moveTo(20f, 10.5f); lineTo(20f, 13.5f) }
    }
    val more = symbol("more") { solid(0f) { dot(5.5f, 12f, 1.9f); dot(12f, 12f, 1.9f); dot(18.5f, 12f, 1.9f) } }
    val chapters = symbol("chapters") {
        line { moveTo(9.5f, 6.5f); lineTo(20f, 6.5f); moveTo(9.5f, 12f); lineTo(20f, 12f); moveTo(9.5f, 17.5f); lineTo(20f, 17.5f) }
        solid(0f) { dot(5f, 6.5f, 1.5f); dot(5f, 12f, 1.5f); dot(5f, 17.5f, 1.5f) }
    }
    /** Stacked frames: a season's episodes. */
    val episodes = symbol("episodes") {
        line { roundRect(3f, 8.5f, 18f, 19.5f, 2f) }
        line { moveTo(6.5f, 5.5f); lineTo(19f, 5.5f); arcTo(2f, 2f, 0f, false, true, 21f, 7.5f); lineTo(21f, 15.5f) }
    }
    val info = symbol("info") {
        line { dot(12f, 12f, 9f) }
        line(2.2f) { moveTo(12f, 11f); lineTo(12f, 16.5f) }
        solid(0f) { dot(12f, 7.6f, 1.3f) }
    }
    /** A gauge: playback speed. */
    val speed = symbol("speed") {
        line { moveTo(4f, 17f); arcTo(8.5f, 8.5f, 0f, true, true, 20f, 17f) }
        line { moveTo(12f, 15f); lineTo(16f, 9f) }
        solid(0f) { dot(12f, 15f, 1.6f) }
    }
    /** A frame with corners: picture size, fit or fill. */
    val picture = symbol("picture") {
        line { roundRect(3f, 5.5f, 21f, 18.5f, 2.5f) }
        line { moveTo(7f, 11f); lineTo(7f, 9f); lineTo(9f, 9f); moveTo(17f, 13f); lineTo(17f, 15f); lineTo(15f, 15f) }
    }
    /** A sun's half: picture tone and the lamp. */
    val tone = symbol("tone") {
        line { dot(12f, 12f, 4f) }
        line { moveTo(12f, 2.8f); lineTo(12f, 4.6f); moveTo(12f, 19.4f); lineTo(12f, 21.2f); moveTo(2.8f, 12f); lineTo(4.6f, 12f)
            moveTo(19.4f, 12f); lineTo(21.2f, 12f); moveTo(5.5f, 5.5f); lineTo(6.8f, 6.8f); moveTo(17.2f, 17.2f); lineTo(18.5f, 18.5f)
            moveTo(18.5f, 5.5f); lineTo(17.2f, 6.8f); moveTo(6.8f, 17.2f); lineTo(5.5f, 18.5f) }
    }
    /** A crescent: the sleep timer. */
    val sleep = symbol("sleep") {
        line { moveTo(19.5f, 14.5f); arcTo(8f, 8f, 0f, true, true, 9.5f, 4.5f); arcTo(6.5f, 6.5f, 0f, false, false, 19.5f, 14.5f); close() }
    }
    val phone = symbol("phone") {
        line { roundRect(7f, 2.5f, 17f, 21.5f, 2.5f) }
        line { moveTo(10.5f, 18f); lineTo(13.5f, 18f) }
    }
    /** Statistics: Playback Info. */
    val stats = symbol("stats") {
        line { moveTo(5f, 20f); lineTo(5f, 13f); moveTo(10f, 20f); lineTo(10f, 8f); moveTo(15f, 20f); lineTo(15f, 11f); moveTo(20f, 20f); lineTo(20f, 4f) }
    }

    // Marks used across the app

    val check = symbol("check") { line(2.4f) { moveTo(5f, 12.5f); lineTo(10f, 17.5f); lineTo(19f, 7f) } }
    val chevronRight = symbol("chevronRight") { line(2.4f) { moveTo(9f, 5f); lineTo(16f, 12f); lineTo(9f, 19f) } }
    val chevronDown = symbol("chevronDown") { line(2.4f) { moveTo(5f, 9f); lineTo(12f, 16f); lineTo(19f, 9f) } }
    val close = symbol("close") { line(2.4f) { moveTo(6f, 6f); lineTo(18f, 18f); moveTo(18f, 6f); lineTo(6f, 18f) } }
    private fun PathBuilder.star() {
        moveTo(12f, 3f); lineTo(14.6f, 8.8f); lineTo(21f, 9.4f); lineTo(16.1f, 13.6f); lineTo(17.6f, 20f)
        lineTo(12f, 16.6f); lineTo(6.4f, 20f); lineTo(7.9f, 13.6f); lineTo(3f, 9.4f); lineTo(9.4f, 8.8f); close()
    }
    val star = symbol("star") { solid { star() } }
    val starOutline = symbol("starOutline") { line { star() } }
    val note = symbol("note") {
        solid(0f) { dot(7.5f, 17.5f, 3f) }
        line { moveTo(10.5f, 17.5f); lineTo(10.5f, 4.5f); lineTo(19f, 3f); lineTo(19f, 7f); lineTo(10.5f, 8.5f) }
    }
    val sort = symbol("sort") {
        line { moveTo(8f, 19f); lineTo(8f, 5f); moveTo(4.5f, 8.5f); lineTo(8f, 5f); lineTo(11.5f, 8.5f)
            moveTo(16f, 5f); lineTo(16f, 19f); moveTo(12.5f, 15.5f); lineTo(16f, 19f); lineTo(19.5f, 15.5f) }
    }
    val download = symbol("download") {
        line { moveTo(12f, 4f); lineTo(12f, 15f); moveTo(7.5f, 10.5f); lineTo(12f, 15f); lineTo(16.5f, 10.5f); moveTo(5f, 19.5f); lineTo(19f, 19.5f) }
    }

    /** Every symbol, for the test that each one builds. */
    val all get() = listOf(play, pause, next, previous, skipBack, skipForward, subtitles, audio, more, chapters, episodes, info,
        speed, picture, tone, sleep, phone, stats, check, chevronRight, chevronDown, close, star, starOutline, note, sort, download)
}

/** A symbol beside text: 16 dp, in the text's colour unless told otherwise. */
@androidx.compose.runtime.Composable
fun Mark(symbol: ImageVector, modifier: androidx.compose.ui.Modifier = androidx.compose.ui.Modifier, size: androidx.compose.ui.unit.Dp = 16.dp,
         tint: Color = androidx.compose.material3.LocalContentColor.current) =
    androidx.compose.material3.Icon(symbol, null, androidx.compose.ui.Modifier.then(modifier).then(androidx.compose.ui.Modifier.size(size)), tint = tint)
