package app.lumiere.android

/**
 * The installed build, as the app module's BuildConfig has it — which the
 * shared modules cannot see. Set by the activity before anything is drawn.
 */
object AppBuild {
    var versionName = ""
        private set
    var versionCode = 0
        private set
    /** The Meta Quest build: the TV layout in a Horizon OS window, updated by sideloading. */
    var quest = false
        private set

    fun set(versionName: String, versionCode: Int, quest: Boolean) {
        this.versionName = versionName; this.versionCode = versionCode; this.quest = quest
    }
}
