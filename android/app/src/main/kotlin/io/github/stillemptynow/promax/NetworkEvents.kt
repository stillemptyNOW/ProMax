package io.github.stillemptynow.promax

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

object NetworkEvents {
    private const val CHANNEL = "io.github.stillemptynow.promax/network_events"
    private const val LOG_TAG = "NetworkEvents"

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var manager: ConnectivityManager? = null

    fun attach(messenger: BinaryMessenger, app: Context) {
        EventChannel(messenger, CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                start(app)
            }

            override fun onCancel(arguments: Any?) = detach()
        })
    }

    fun detach() {
        stop()
        sink = null
    }

    private fun start(app: Context) {
        if (callback != null) return
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val watcher = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post { sink?.success("available") }
            }

            override fun onLost(network: Network) {
                main.post { if (cm.activeNetwork == null) sink?.success("lost") }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                cm.registerDefaultNetworkCallback(watcher)
            } else {
                cm.registerNetworkCallback(
                    NetworkRequest.Builder()
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        .build(),
                    watcher,
                )
            }
            callback = watcher
            manager = cm
            if (cm.activeNetwork == null) sink?.success("lost")
        } catch (e: Exception) {
            Log.w(LOG_TAG, "network watch failed: ${e.message}")
        }
    }

    private fun stop() {
        val watcher = callback ?: return
        callback = null
        try {
            manager?.unregisterNetworkCallback(watcher)
        } catch (_: Exception) {
        }
        manager = null
    }
}
