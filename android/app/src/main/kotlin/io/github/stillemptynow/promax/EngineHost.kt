package io.github.stillemptynow.promax

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

interface LaunchHost {
    fun consumeInitialChat(): Long?
    fun consumeInitialCall(): Map<String, Any?>?
    fun consumeInitialShare(result: MethodChannel.Result)
    fun clearCallWindowFlags()
}

object EngineHost {
    private const val INITIAL_ROUTE = "/"

    private val main = Handler(Looper.getMainLooper())

    private var engine: FlutterEngine? = null

    var activity: Activity? = null
        private set

    val launch: LaunchHost?
        get() = activity as? LaunchHost

    fun ensure(ctx: Context, headless: Boolean): FlutterEngine {
        val app = ctx.applicationContext
        synchronized(AudioServicePlugin::class.java) {
            val id = AudioServicePlugin.getFlutterEngineId()
            val cached = FlutterEngineCache.getInstance().get(id)
            if (cached != null) {
                attach(cached, app)
                if (headless && activity == null) cached.lifecycleChannel.appIsDetached()
                return cached
            }
            val created = FlutterEngine(app)
            attach(created, app)
            if (headless) created.lifecycleChannel.appIsDetached()
            created.navigationChannel.setInitialRoute(INITIAL_ROUTE)
            created.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            FlutterEngineCache.getInstance().put(id, created)
            return created
        }
    }

    fun releaseHeadless() {
        if (activity != null || engine == null) return
        main.post {
            if (activity == null) AudioServicePlugin.disposeFlutterEngine()
        }
    }

    fun bindActivity(host: Activity, target: FlutterEngine) {
        attach(target, host.applicationContext)
        activity = host
    }

    fun unbindActivity(host: Activity) {
        if (activity !== host) return
        activity = null
        ChatNotifications.activeChatId = 0L
        FkmChannel.onActivityGone()
    }

    private fun attach(target: FlutterEngine, app: Context) {
        if (engine === target) return
        val late = target.dartExecutor.isExecutingDart
        engine = target
        val messenger = target.dartExecutor.binaryMessenger
        FkmChannel.attach(messenger, app)
        LauncherBadge.attach(messenger, app)
        ChatNotifications.attach(messenger, app)
        CallChannel.attach(messenger, app)
        ShareIntake.attach(messenger, app)
        target.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() = Unit

            override fun onEngineWillDestroy() = onDestroyed(target, app)
        })
        if (late) FkmChannel.announce()
    }

    private fun onDestroyed(target: FlutterEngine, app: Context) {
        val cache = FlutterEngineCache.getInstance()
        val id = AudioServicePlugin.getFlutterEngineId()
        if (cache.get(id) === target) cache.remove(id)
        if (engine !== target) return
        engine = null
        FkmChannel.detach()
        LauncherBadge.detach()
        ChatNotifications.sink = null
        ChatNotifications.activeChatId = 0L
        CallEvents.sink = null
        ShareIntake.sink = null
        FkmState.connected = false
        FkmService.refresh(app)
        main.post { FkmService.restoreEngine() }
    }
}

fun longArg(value: Any?): Long = when (value) {
    is Int -> value.toLong()
    is Long -> value
    else -> 0L
}
