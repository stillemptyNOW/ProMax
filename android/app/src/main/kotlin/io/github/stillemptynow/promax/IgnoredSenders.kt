package io.github.stillemptynow.promax

import android.content.Context
import org.json.JSONObject

object IgnoredSenders {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.promax_ignored_senders"

    fun hidesPush(ctx: Context, data: Map<String, String>): Boolean {
        val chatId = data["mc"]?.toLongOrNull() ?: return false
        val senderId = data["suid"]?.toLongOrNull() ?: return false
        return hidesMessage(ctx, chatId, senderId)
    }

    fun hidesMessage(ctx: Context, chatId: Long, senderId: Long): Boolean {
        if (chatId <= 0L || senderId <= 0L) return false
        return accountsIgnoring(ctx, senderId).any { account -> (account xor senderId) == chatId }
    }

    fun hidesCall(ctx: Context, callerId: Long): Boolean =
        callerId > 0L && accountsIgnoring(ctx, callerId).isNotEmpty()

    private fun accountsIgnoring(ctx: Context, userId: Long): List<Long> {
        val raw = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null) ?: return emptyList()
        val map = try {
            JSONObject(raw)
        } catch (e: Exception) {
            return emptyList()
        }
        val accounts = ArrayList<Long>()
        val keys = map.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val account = key.toLongOrNull() ?: continue
            val ids = map.optJSONArray(key) ?: continue
            for (i in 0 until ids.length()) {
                if (ids.optLong(i, 0L) == userId) {
                    accounts.add(account)
                    break
                }
            }
        }
        return accounts
    }
}
