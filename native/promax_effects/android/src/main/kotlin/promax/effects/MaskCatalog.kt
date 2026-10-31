package promax.effects

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal class MaskStyle(
    val id: String,
    val spec: DoubleArray,
    val pixelate: Boolean,
    val image: Bitmap?,
)

internal class MaskCatalog(
    private val assets: AssetManager,
    private val resolve: (String) -> String,
) {
    private val styles = HashMap<String, MaskStyle>()
    private var entries: Map<String, JSONObject>? = null

    fun style(id: String): MaskStyle? {
        styles[id]?.let { return it }
        val entry = entries().get(id) ?: return null
        val anchor = NativeEffects.maskAnchor(entry.optString("anchor", ""))
        if (anchor < 0) return null
        val pixelate = entry.optString("effect", "") == "pixelate"
        val width = number(entry.opt("scale"), 0.0)
        var image: Bitmap? = null
        val aspect: Double
        if (pixelate) {
            aspect = number(entry.opt("aspect"), 1.0)
        } else {
            val asset = entry.optString("asset", "")
            if (asset.isEmpty()) return null
            val source = decode(asset) ?: return null
            aspect = source.height.toDouble() / source.width.toDouble()
            image = powerOfTwo(source)
        }
        if (!(width > 0) || !(aspect > 0)) return null
        val offset = entry.optJSONArray("offset")
        val pivot = entry.optJSONArray("pivot")
        val spec = doubleArrayOf(
            anchor.toDouble(),
            width,
            aspect,
            component(offset, 0, 0.0),
            component(offset, 1, 0.0),
            component(pivot, 0, 0.5),
            component(pivot, 1, 0.5),
            number(entry.opt("depth"), 0.0),
        )
        val style = MaskStyle(id, spec, pixelate, image)
        styles[id] = style
        return style
    }

    private fun entries(): Map<String, JSONObject> {
        entries?.let { return it }
        val loaded = HashMap<String, JSONObject>()
        try {
            val text = assets.open(resolve("$DIRECTORY/masks.json")).use { stream ->
                stream.readBytes().toString(Charsets.UTF_8)
            }
            val masks = JSONObject(text).optJSONArray("masks")
            if (masks != null) {
                for (index in 0 until masks.length()) {
                    val entry = masks.optJSONObject(index) ?: continue
                    val id = entry.optString("id", "")
                    if (id.isNotEmpty()) loaded[id] = entry
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "Mask manifest is unavailable", error)
        }
        entries = loaded
        return loaded
    }

    private fun decode(asset: String): Bitmap? {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false
        }
        val bitmap = try {
            assets.open(resolve("$DIRECTORY/$asset")).use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            }
        } catch (error: Exception) {
            Log.w(TAG, "Mask artwork $asset is unavailable", error)
            null
        } ?: return null
        if (bitmap.width < 1 || bitmap.height < 1) return null
        return bitmap
    }

    private fun powerOfTwo(source: Bitmap): Bitmap {
        val width = ceilPowerOfTwo(source.width)
        val height = ceilPowerOfTwo(source.height)
        if (width == source.width && height == source.height && source.config == Bitmap.Config.ARGB_8888) {
            return source
        }
        return Bitmap.createScaledBitmap(source, width, height, true)
    }

    private fun ceilPowerOfTwo(value: Int): Int {
        var size = 1
        while (size < value.coerceAtMost(MAX_TEXTURE)) size = size shl 1
        return size
    }

    private fun number(value: Any?, fallback: Double): Double {
        val number = (value as? Number)?.toDouble() ?: return fallback
        return if (number.isFinite()) number else fallback
    }

    private fun component(values: JSONArray?, index: Int, fallback: Double): Double {
        if (values == null || index >= values.length()) return fallback
        return number(values.opt(index), fallback)
    }

    companion object {
        const val PACKAGE = "promax_effects"
        const val DIRECTORY = "ios/Resources/masks"
        private const val MAX_TEXTURE = 512
        private const val TAG = "ProMaxEffects"
    }
}
