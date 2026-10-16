package io.github.stillemptynow.promax

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

object FkmChannel {
    private const val NAME = "io.github.stillemptynow.promax/fkm"
    const val NOTIF_PERMS_REQUEST = 7713

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private var channel: MethodChannel? = null
    private var permResult: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger, ctx: Context) {
        val app = ctx.applicationContext
        FkmState.restore(app)
        val ch = MethodChannel(messenger, NAME)
        channel = ch
        ch.setMethodCallHandler { call, result -> handle(app, call, result) }
    }

    private fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> result.success(FkmState.enabled)

            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                FkmState.applyEnabled(ctx, enabled)
                if (enabled) FkmService.start(ctx) else FkmService.stop(ctx)
                result.success(null)
            }

            "setConnected" -> {
                FkmState.connected = call.argument<Boolean>("connected") ?: false
                FkmService.refresh(ctx)
                result.success(null)
            }

            "showMessage" -> result.success(deliver(ctx, call, "showMessage"))

            "showCall" -> result.success(deliver(ctx, call, "showCall"))

            "editMessage" -> result.success(
                update(ctx, call, "editMessage") { notifier, data ->
                    notifier.editMessage(data)
                },
            )

            "removeMessage" -> result.success(
                update(ctx, call, "removeMessage") { notifier, data ->
                    notifier.removeMessage(data)
                },
            )

            "hasNotificationPermission" ->
                result.success(NotificationManagerCompat.from(ctx).areNotificationsEnabled())

            "requestNotificationPermission" -> requestNotificationPermission(ctx, result)

            "isIgnoringBatteryOptimizations" -> {
                val power = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(power.isIgnoringBatteryOptimizations(ctx.packageName))
            }

            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations(ctx)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(ctx: Context, result: MethodChannel.Result) {
        val granted = NotificationManagerCompat.from(ctx).areNotificationsEnabled()
        val activity = EngineHost.activity
        if (granted || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || activity == null) {
            result.success(granted)
            return
        }
        permResult?.success(false)
        permResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIF_PERMS_REQUEST,
        )
    }

    private fun requestIgnoreBatteryOptimizations(ctx: Context) {
        val activity = EngineHost.activity
        if (activity == null) {
            Log.w("Fkm", "battery settings skipped: no activity")
            return
        }
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${ctx.packageName}"),
                ),
            )
        } catch (e: Exception) {
            Log.w("Fkm", "battery settings failed: ${e.message}")
        }
    }

    // Отрисовка тянет аватарку по сети — только не на главном потоке.
    private fun deliver(ctx: Context, call: MethodCall, tag: String): Boolean {
        val data = call.argument<Map<String, String>>("data") ?: return false
        worker.execute {
            try {
                ProMaxNotifier(ctx).handle(data)
                FkmState.countDelivered(ctx)
                FkmService.refresh(ctx)
            } catch (e: Exception) {
                Log.w("Fkm", "$tag failed: ${e.message}")
            }
        }
        return true
    }

    // Правка и удаление ничего не «доставляют» — счётчик они не трогают.
    private fun update(
        ctx: Context,
        call: MethodCall,
        tag: String,
        action: (ProMaxNotifier, Map<String, String>) -> Unit,
    ): Boolean {
        val data = call.argument<Map<String, String>>("data") ?: return false
        worker.execute {
            try {
                action(ProMaxNotifier(ctx), data)
            } catch (e: Exception) {
                Log.w("Fkm", "$tag failed: ${e.message}")
            }
        }
        return true
    }

    fun onActivityGone() {
        permResult?.success(false)
        permResult = null
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        permResult = null
    }

    fun onPermissionResult(grantResults: IntArray) {
        val pending = permResult ?: return
        permResult = null
        pending.success(
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED },
        )
    }

    fun announce() = send("attached")

    fun notifyDisabled() = send("disabled")

    private fun send(method: String) {
        main.post {
            try {
                channel?.invokeMethod(method, null)
            } catch (e: Exception) {
                Log.w("Fkm", "$method failed: ${e.message}")
            }
        }
    }
}
