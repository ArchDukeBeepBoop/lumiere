package app.lumiere.android

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity

/**
 * The Quest's window lets the room drive it (see [OpenApp]): the controllers'
 * buttons arrive as a TV remote's keys, through the window's own [dispatch], and a thumbstick held up or down as a
 * little scroll each frame, as a trackpad's, where the page is.
 */
internal fun ComponentActivity.hostInTheRoom(state: AppState, dispatch: (KeyEvent) -> Boolean) {
    OpenApp.state = state
    OpenApp.press = { code ->
        runOnUiThread {
            val now = android.os.SystemClock.uptimeMillis()
            dispatch(KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0))
            dispatch(KeyEvent(now, now, KeyEvent.ACTION_UP, code, 0))
        }
    }
    OpenApp.scroll = { amount ->
        runOnUiThread {
            val root = window.decorView
            val now = android.os.SystemClock.uptimeMillis()
            val props = MotionEvent.PointerProperties().apply { id = 0; toolType = MotionEvent.TOOL_TYPE_MOUSE }
            val coords = MotionEvent.PointerCoords().apply {
                x = root.width / 2f; y = root.height * 0.6f
                setAxisValue(MotionEvent.AXIS_VSCROLL, amount)
            }
            val e = MotionEvent.obtain(now, now, MotionEvent.ACTION_SCROLL, 1, arrayOf(props), arrayOf(coords),
                0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_MOUSE, 0)
            root.dispatchGenericMotionEvent(e)
            e.recycle()
        }
    }
}

/** The window is going: the room stops driving it. */
internal fun leaveTheRoom(state: AppState) {
    if (OpenApp.state === state) { OpenApp.state = null; OpenApp.press = null; OpenApp.scroll = null }
}
