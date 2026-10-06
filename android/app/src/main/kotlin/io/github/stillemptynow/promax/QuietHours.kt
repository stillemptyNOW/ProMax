package io.github.stillemptynow.promax

import android.content.Context
import org.json.JSONObject
import java.util.Calendar

object QuietHours {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.promax_quiet_hours"

    fun isQuiet(ctx: Context, chatId: Long, now: Calendar = Calendar.getInstance()): Boolean {
        val window = try {
            val raw = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(KEY, null) ?: return false
            JSONObject(raw).optJSONObject(chatId.toString()) ?: return false
        } catch (e: Exception) {
            return false
        }
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
