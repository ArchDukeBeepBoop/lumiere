package app.lumiere.android

/**
 * The open window, for whatever hosts it. On the Quest the window is a panel
 * inside the room (app/src/quest's LumiereSpace), and the room needs to press
 * the window's keys for the controllers, scroll it for the thumbsticks, and
 * be the one that quits. Unset on the phone and TV, where nothing else hosts
 * the window and every caller falls back to the activity's own way.
 */
object OpenApp {
    /** The open window's state, while it is open. */
    @Volatile var state: AppState? = null
    /** Leaves the whole app: on the Quest the room, of which this window is only a panel. */
    @Volatile var quit: (() -> Unit)? = null
    /** Presses a remote key in the window, as a TV remote would. */
    @Volatile var press: ((Int) -> Unit)? = null
    /** Scrolls the window by [amount] wheel steps (up positive), where its page is. */
    @Volatile var scroll: ((Float) -> Unit)? = null
    /** The film the Quest's theater was opened for, until its window starts it. */
    @Volatile var pendingPlay: Screen.Player? = null
}
