package app.lumiere.android

/**
 * Which of the three apps this is — the phone's, the TV's or the Quest's —
 * fixed when it is built (app/build.gradle.kts), never guessed from the device.
 */
object Flavor {
    val tv = BuildConfig.DEVICE == "tv"
    val phone = BuildConfig.DEVICE == "phone"
    val quest = BuildConfig.DEVICE == "quest"

    /** The phone remote is for the TV alone: the TV listens, only the phone controls it. */
    val listensForRemote get() = tv
    val isRemote get() = phone
}
