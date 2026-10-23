package io.github.stillemptynow.promax

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper

object ScreenShareWatcher {
    const val EVENT_STOPPED = "screenShareStopped"
    private const val CAPTURE_DISPLAY = "WebRTC_ScreenCapture"

    private val main = Handler(Looper.getMainLooper())
    private var manager: DisplayManager? = null
    private val captures = mutableSetOf<Int>()

    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {
            remember(displayId)
        }

        override fun onDisplayChanged(displayId: Int) {
            remember(displayId)
        }

        override fun onDisplayRemoved(displayId: Int) {
            if (manager == null || !captures.remove(displayId) || captures.isNotEmpty()) return
            stop()
            CallEvents.emit(EVENT_STOPPED)
        }
    }

    fun start(ctx: Context) {
        if (manager != null) return
        val dm = ctx.applicationContext.getSystemService(DisplayManager::class.java) ?: return
        manager = dm
        captures.clear()
        dm.registerDisplayListener(listener, main)
        for (display in dm.displays) remember(display.displayId)
    }

    fun stop() {
        val dm = manager ?: return
        manager = null
        captures.clear()
        dm.unregisterDisplayListener(listener)
    }

    private fun remember(displayId: Int) {
        val display = manager?.getDisplay(displayId) ?: return
        if (display.name == CAPTURE_DISPLAY) captures.add(displayId)
    }
}
