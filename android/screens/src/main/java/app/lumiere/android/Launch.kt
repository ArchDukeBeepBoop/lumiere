package app.lumiere.android

import android.content.Context
import android.content.Intent

/** Lumiere's window, for widgets and the TV's Watch Next row — the activity lives in the app module. */
object Launch {
    fun intent(context: Context): Intent = Intent().setClassName(context, "app.lumiere.android.MainActivity")
}
