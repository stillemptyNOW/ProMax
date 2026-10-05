package io.github.stillemptynow.promax

import android.content.Intent
import io.flutter.plugin.common.EventChannel

object ChatNotifications {
    const val EXTRA_CHAT = "promax_chat"

    @Volatile
    var activeChatId: Long = 0L

    @Volatile
    var sink: EventChannel.EventSink? = null

    fun isDisplayed(chatId: Long): Boolean =
        AppState.resumed && activeChatId == chatId

    fun chatIdFrom(intent: Intent?): Long =
        intent?.getLongExtra(EXTRA_CHAT, 0L) ?: 0L
}
