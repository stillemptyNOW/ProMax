package io.github.stillemptynow.promax

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class CallPip(private val activity: Activity) {

    companion object {
        const val METHODS = "io.github.stillemptynow.promax/call_pip"
        const val EVENTS = "io.github.stillemptynow.promax/call_pip_events"
        private const val ACTION_MUTE = "io.github.stillemptynow.promax.CALL_PIP_MUTE"
        private const val ACTION_HANGUP = "io.github.stillemptynow.promax.CALL_PIP_HANGUP"
        private const val REQUEST_MUTE = 7801
        private const val REQUEST_HANGUP = 7802
        private const val TAG = "CallPip"
        private const val MAX_RATIO = 239f / 100f
    }

    private var eligible = false
    private var muted = false
    private var ratioWidth = 9
    private var ratioHeight = 16
    private var sink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_MUTE -> emit(mapOf("event" to "action", "action" to "mute"))
                ACTION_HANGUP -> emit(mapOf("event" to "action", "action" to "hangup"))
            }
        }
    }

    private val supported: Boolean by lazy {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    update(
                        eligible = call.argument<Boolean>("eligible") ?: false,
                        muted = call.argument<Boolean>("muted") ?: false,
                        width = call.argument<Number>("width")?.toInt() ?: 0,
                        height = call.argument<Number>("height")?.toInt() ?: 0,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    events?.success(mapOf("event" to "mode", "pip" to activity.isInPictureInPictureMode))
                }
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    fun detach() {
        sink = null
        eligible = false
        unregisterReceiver()
    }

    fun onUserLeaveHint() {
        if (!eligible || !supported) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (activity.isInPictureInPictureMode) return
        try {
            activity.enterPictureInPictureMode(buildParams())
        } catch (e: Exception) {
            Log.w(TAG, "enter failed: ${e.message}")
        }
    }

    fun onModeChanged(inPip: Boolean) {
        emit(mapOf("event" to "mode", "pip" to inPip))
    }

    private fun update(eligible: Boolean, muted: Boolean, width: Int, height: Int) {
        val wasEligible = this.eligible
        this.eligible = eligible && supported
        this.muted = muted
        if (width > 0 && height > 0) {
            ratioWidth = width
            ratioHeight = height
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !supported) return
        if (this.eligible) registerReceiver()
        applyParams()
        if (this.eligible || !wasEligible) return
        unregisterReceiver()
        if (activity.isInPictureInPictureMode) activity.moveTaskToBack(false)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun applyParams() {
        try {
            activity.setPictureInPictureParams(buildParams())
        } catch (e: Exception) {
            Log.w(TAG, "params failed: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspectRatio())
            .setActions(if (eligible) actions() else emptyList())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(eligible)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun aspectRatio(): Rational {
        val ratio = ratioWidth.toFloat() / ratioHeight.toFloat()
        return when {
            ratio > MAX_RATIO -> Rational(239, 100)
            ratio < 1f / MAX_RATIO -> Rational(100, 239)
            else -> Rational(ratioWidth, ratioHeight)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun actions(): List<RemoteAction> {
        val muteTitle = activity.getString(
            if (muted) R.string.call_pip_unmute else R.string.call_pip_mute,
        )
        val hangupTitle = activity.getString(R.string.call_pip_hangup)
        return listOf(
            RemoteAction(
                Icon.createWithResource(
                    activity,
                    if (muted) R.drawable.ic_pip_mic_off else R.drawable.ic_pip_mic,
                ),
                muteTitle,
                muteTitle,
                broadcast(ACTION_MUTE, REQUEST_MUTE),
            ),
            RemoteAction(
                Icon.createWithResource(activity, R.drawable.ic_pip_call_end),
                hangupTitle,
                hangupTitle,
                broadcast(ACTION_HANGUP, REQUEST_HANGUP),
            ),
        )
    }

    private fun broadcast(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            activity,
            requestCode,
            Intent(action).setPackage(activity.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(ACTION_MUTE)
            addAction(ACTION_HANGUP)
        }
        ContextCompat.registerReceiver(
            activity,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!receiverRegistered) return
        receiverRegistered = false
        try {
            activity.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "unregister failed: ${e.message}")
        }
    }

    private fun emit(event: Map<String, Any>) {
        sink?.success(event)
    }
}
