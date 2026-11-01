package io.github.stillemptynow.promax

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object ChatNotifications {
    const val EXTRA_CHAT = "promax_chat"
    private const val METHODS = "io.github.stillemptynow.promax/notifications"
    private const val EVENTS = "io.github.stillemptynow.promax/notification_events"

    @Volatile
    var activeChatId: Long = 0L

    @Volatile
    var sink: EventChannel.EventSink? = null

    fun isDisplayed(chatId: Long): Boolean =
        AppState.resumed && activeChatId == chatId

    fun chatIdFrom(intent: Intent?): Long =
        intent?.getLongExtra(EXTRA_CHAT, 0L) ?: 0L

    fun attach(messenger: BinaryMessenger, ctx: Context) {
        val app = ctx.applicationContext
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialChat" ->
                    result.success(EngineHost.launch?.consumeInitialChat())
                "setActiveChat" -> {
                    activeChatId = longArg(call.argument<Any>("chatId"))
                    result.success(null)
                }
                "clearActiveChat" -> {
                    activeChatId = 0L
                    result.success(null)
                }
                "cancelChat" -> {
                    ProMaxNotifier(app).cancelChat(longArg(call.argument<Any>("chatId")))
                    result.success(null)
                }
                "pruneChat" -> {
                    val chatId = longArg(call.argument<Any>("chatId"))
                    val seen = longArg(call.argument<Any>("seen"))
                    FkmChannel.post("pruneChat") { ProMaxNotifier(app).pruneChat(chatId, seen) }
                    result.success(null)
                }
                "notifiedChats" -> result.success(ProMaxNotifier(app).notifiedChats())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }
}
