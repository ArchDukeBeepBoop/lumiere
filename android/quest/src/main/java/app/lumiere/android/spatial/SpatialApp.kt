package app.lumiere.android.spatial

import android.app.Application
import app.lumiere.android.AppBuild

/** Lumiere on a Quest: the shared modules take the TV layout and leave updates to sideloading. */
class SpatialApp : Application() {
    override fun onCreate() {
        AppBuild.set(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, quest = true)
        super.onCreate()
    }
}
