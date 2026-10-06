package io.github.stillemptynow.promax

import android.content.Context
import org.json.JSONObject
import java.util.Calendar

object QuietHours {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.promax_quiet_hours"
    private const val GLOBAL_KEY = "flutter.promax_quiet_hours_global"

    fun isQuiet(ctx: Context, chatId: Long, now: Calendar = Calendar.getInstance()): Boolean {
        val prefs = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val global = parse(prefs.getString(GLOBAL_KEY, null))
        if (global != null && covers(global, now)) return true
        val perChat = parse(prefs.getString(KEY, null))?.optJSONObject(chatId.toString())
        return perChat != null && covers(perChat, now)
    }

    private fun parse(raw: String?): JSONObject? = try {
        raw?.let { JSONObject(it) }
    } catch (e: Exception) {
        null
    }

    private fun covers(window: JSONObject, now: Calendar): Boolean {
        val start = window.optInt("s", -1)
        val end = window.optInt("e", -1)
        if (start !in 0..23 || end !in 0..23) return false
        val weekday = now.get(Calendar.DAY_OF_WEEK)
        if (window.optBoolean("w") && (weekday == Calendar.SATURDAY || weekday == Calendar.SUNDAY)) {
            return false
        }
        val hour = now.get(Calendar.HOUR_OF_DAY)
        return when {
            start == end -> true
            start < end -> hour in start until end
            else -> hour >= start || hour < end
        }
    }
}
