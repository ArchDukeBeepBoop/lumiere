package app.lumiere.android

import android.app.Application

/** The phone and TV app: tells the shared modules which build this is, before any window opens. */
class LumiereApp : Application() {
    override fun onCreate() {
        AppBuild.set(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.QUEST)
        super.onCreate()
        CrashLog.install(this)
    }
}
