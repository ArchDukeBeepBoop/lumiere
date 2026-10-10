package app.lumiere.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lumiere.android.CrashLog

/**
 * "Lumiere stopped last time", shown once at the next start: the error and
 * the lines of it in Lumiere's own code or the Meta SDK's, small enough to
 * read or photograph on a headset and send on. The whole report is also in
 * Downloads › Lumiere.
 */
@Composable
fun CrashReportDialog(report: String, onDone: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 1000.dp).padding(24.dp).background(Palette.surface, RoundedCornerShape(20.dp)).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Lumiere stopped last time", style = MaterialTheme.typography.headlineSmall)
            Text("This is what went wrong. A photo of it is all that's needed to fix it " +
                "(the whole report is in Downloads › Lumiere).", color = Palette.textSecondary)
            Text(CrashLog.essentials(report), style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp, lineHeight = 17.sp),
                color = Palette.textPrimary,
                modifier = Modifier.fillMaxWidth().heightIn(max = 460.dp).background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
                    .verticalScroll(rememberScrollState()).padding(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                LButton(onClick = onDone) { Text("Done") }
            }
        }
    }
}
