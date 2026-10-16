package io.github.stillemptynow.promax

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object CallChannel {
    private const val METHODS = "io.github.stillemptynow.promax/calls"
    private const val EVENTS = "io.github.stillemptynow.promax/calls_events"
    private const val DEFAULT_CALLER = "Звонок"

    fun attach(messenger: BinaryMessenger, ctx: Context) {
        val app = ctx.applicationContext
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialCall" -> result.success(EngineHost.launch?.consumeInitialCall())
                "notifyAccepted" -> {
                    val caller = call.argument<String>("caller") ?: DEFAULT_CALLER
                    CallRinger.stop()
                    NotificationManagerCompat.from(app).cancel(CallConst.NOTIF_ID)
                    CallForegroundService.start(app, caller)
                    result.success(null)
                }
                "ensureOngoing" -> {
                    val caller = call.argument<String>("caller") ?: DEFAULT_CALLER
                    CallForegroundService.start(app, caller)
                    result.success(null)
                }
                "setScreenShare" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val caller = call.argument<String>("caller") ?: DEFAULT_CALLER
                    CallForegroundService.setScreenShare(app, enabled, caller)
                    result.success(null)
                }
                "dropOngoing" -> {
                    CallForegroundService.stop(app)
                    result.success(null)
                }
                "notifyEnded" -> {
                    CallRinger.stop()
                    NotificationManagerCompat.from(app).cancel(CallConst.NOTIF_ID)
                    CallForegroundService.stop(app)
                    EngineHost.launch?.clearCallWindowFlags()
                    result.success(null)
                }
                "cancelIncoming" -> {
                    CallRinger.stop()
                    NotificationManagerCompat.from(app).cancel(CallConst.NOTIF_ID)
                    result.success(null)
                }
                "canUseFullScreenIntent" ->
                    result.success(NotificationManagerCompat.from(app).canUseFullScreenIntent())
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                CallEvents.sink = events
            }

            override fun onCancel(arguments: Any?) {
                CallEvents.sink = null
            }
        })
    }

    private fun openFullScreenIntentSettings(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val activity = EngineHost.activity
        if (activity == null) {
            Log.w("ProMaxFcm", "open FSI settings skipped: no activity")
            return
        }
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:${ctx.packageName}"),
                ),
            )
        } catch (e: Exception) {
            Log.w("ProMaxFcm", "open FSI settings failed: ${e.message}")
        }
    }
}
