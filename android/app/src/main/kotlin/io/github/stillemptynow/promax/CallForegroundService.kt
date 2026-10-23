package io.github.stillemptynow.promax

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.ServiceCompat

object CallState {
    @Volatile
    var inCall = false
}

internal class PendingPromotion(private val done: (Boolean) -> Unit) {
    private var delivered = false

    fun deliver(ok: Boolean) {
        if (delivered) return
        delivered = true
        done(ok)
    }
}

class CallForegroundService : Service() {

    companion object {
        const val ACTION_START = "io.github.stillemptynow.promax.CALL_ONGOING_START"
        const val ACTION_STOP = "io.github.stillemptynow.promax.CALL_ONGOING_STOP"
        const val ACTION_SCREEN_SHARE = "io.github.stillemptynow.promax.CALL_SCREEN_SHARE"
        const val ONGOING_ID = 424243
        private const val DEFAULT_CALLER = "Звонок"
        private const val PROMOTE_TIMEOUT_MS = 5000L

        @Volatile
        var screenShare = false

        @Volatile
        internal var running: CallForegroundService? = null

        private val main = Handler(Looper.getMainLooper())
        private var pendingPromotion: PendingPromotion? = null

        fun setScreenShare(
            ctx: Context,
            enabled: Boolean,
            caller: String?,
            done: (Boolean) -> Unit,
        ) {
            val service = running
            if (service != null) {
                done(service.applyScreenShare(enabled, caller))
                return
            }
            if (!enabled) {
                screenShare = false
                ScreenShareWatcher.stop()
                done(true)
                return
            }
            pendingPromotion?.deliver(false)
            val pending = PendingPromotion(done)
            pendingPromotion = pending
            val intent = Intent(ctx, CallForegroundService::class.java).apply {
                action = ACTION_SCREEN_SHARE
                if (caller != null) putExtra(CallConst.EXTRA_CALLER, caller)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (e: Exception) {
                Log.w("ProMaxFcm", "screen share FGS start failed: ${e.message}")
                finishPromotion(false)
                return
            }
            main.postDelayed({ if (pendingPromotion === pending) finishPromotion(false) }, PROMOTE_TIMEOUT_MS)
        }

        private fun finishPromotion(ok: Boolean) {
            val pending = pendingPromotion ?: return
            pendingPromotion = null
            pending.deliver(ok)
        }

        fun start(ctx: Context, caller: String) {
            CallState.inCall = true
            val intent = Intent(ctx, CallForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(CallConst.EXTRA_CALLER, caller)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (e: Exception) {
                Log.w("ProMaxFcm", "ongoing FGS start failed: ${e.message}")
            }
        }

        fun stop(ctx: Context) {
            CallState.inCall = false
            screenShare = false
            ScreenShareWatcher.stop()
            finishPromotion(false)
            val service = running
            if (service != null) {
                service.shutdown()
                return
            }
            NotificationManagerCompat.from(ctx).cancel(ONGOING_ID)
            try {
                ctx.startService(
                    Intent(ctx, CallForegroundService::class.java).apply {
                        action = ACTION_STOP
                    },
                )
            } catch (_: Exception) {
            }
        }
    }

    private var caller = DEFAULT_CALLER

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onDestroy() {
        if (running === this) running = null
        CallState.inCall = false
        screenShare = false
        ScreenShareWatcher.stop()
        finishPromotion(false)
        super.onDestroy()
    }

    private fun shutdown() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(CallConst.EXTRA_CALLER)?.let { caller = it }
        when (intent?.action) {
            ACTION_STOP -> shutdown()
            ACTION_SCREEN_SHARE -> {
                CallNotifier.ensureChannel(this)
                val ok = enableProjection()
                finishPromotion(ok)
                if (!ok && !promote(false)) stopSelf()
            }
            else -> {
                CallNotifier.ensureChannel(this)
                if (promote(screenShare)) return START_NOT_STICKY
                if (screenShare && promote(false)) {
                    screenShare = false
                    ScreenShareWatcher.stop()
                    return START_NOT_STICKY
                }
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun applyScreenShare(enabled: Boolean, newCaller: String?): Boolean {
        if (newCaller != null) caller = newCaller
        CallNotifier.ensureChannel(this)
        if (!enabled) {
            screenShare = false
            ScreenShareWatcher.stop()
            return promote(false)
        }
        if (enableProjection()) return true
        promote(false)
        return false
    }

    private fun enableProjection(): Boolean {
        if (promote(true)) {
            screenShare = true
            ScreenShareWatcher.start(this)
            return true
        }
        screenShare = false
        ScreenShareWatcher.stop()
        return false
    }

    private fun promote(projection: Boolean): Boolean {
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        if (projection) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        return try {
            ServiceCompat.startForeground(this, ONGOING_ID, buildNotification(), types)
            true
        } catch (e: Exception) {
            Log.w("ProMaxFcm", "startForeground(projection=$projection) failed: ${e.message}")
            false
        }
    }

    private fun buildNotification(): Notification {
        val immutable = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
            android.app.PendingIntent.FLAG_IMMUTABLE
        val open = LaunchIntents.app(this).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pi = android.app.PendingIntent.getActivity(this, 4, open, immutable)
        val hangup = android.app.PendingIntent.getBroadcast(
            this, 5,
            Intent(this, CallActionReceiver::class.java).apply {
                action = CallConst.ACTION_HANGUP
            },
            immutable,
        )
        val person = Person.Builder().setName(caller).build()
        return NotificationCompat.Builder(this, CallConst.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(CallConst.ACCENT)
            .setColorized(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .setStyle(NotificationCompat.CallStyle.forOngoingCall(person, hangup))
            .build()
    }
}
