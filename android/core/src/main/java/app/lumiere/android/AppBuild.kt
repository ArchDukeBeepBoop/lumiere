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

    /** The source it was built from (a git commit), and when it was built: to tell one sideloaded build from another. */
    var commit = ""
        private set
    var builtAt = 0L
        private set

    fun set(versionName: String, versionCode: Int, quest: Boolean, commit: String = "", builtAt: Long = 0L) {
        this.versionName = versionName; this.versionCode = versionCode; this.quest = quest
        this.commit = commit; this.builtAt = builtAt
    }

    /** One line naming this build, as Home and Diagnostics show it. */
    val stamp: String get() = buildString {
        append("Build ").append(versionName)
        if (commit.isNotEmpty()) append(" · ").append(commit)
        if (builtAt > 0) append(" · built ").append(java.text.SimpleDateFormat("d MMM HH:mm 'UTC'", java.util.Locale.ROOT)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date(builtAt)))
    }
}
