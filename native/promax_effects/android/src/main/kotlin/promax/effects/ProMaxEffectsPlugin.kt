package promax.effects

import android.app.Activity
import android.content.Context
import android.view.Window
import android.view.WindowManager
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ProMaxEffectsPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var catalog: MaskCatalog? = null
    private var masks: MaskProcessor? = null
    private var track: LocalVideoTrack? = null
    private var voice: VoiceEffect? = null
    private var audio: AudioProcessingAdapter? = null
    private var lightBrightness: Float? = null
    private var litWindow: Window? = null
    private var originalBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val assets = binding.flutterAssets
        catalog = MaskCatalog(binding.applicationContext.assets) { name ->
            assets.getAssetFilePathByName(name, MaskCatalog.PACKAGE)
        }
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        reset()
        masks?.close()
        masks = null
        voice?.release()
        voice = null
        catalog = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        applyLight()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        applyLight()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setScreenLight" -> {
                val value = (call.argument<Any>("brightness") as? Number)?.toDouble()
                if (value == null || !value.isFinite() || value < 0.1 || value > 1.0) {
                    result.error("BAD_BRIGHTNESS", "Некорректная яркость", null)
                    return
                }
                lightBrightness = value.toFloat()
                applyLight()
            }
            "restoreScreenBrightness" -> restoreBrightness()
            "setVoice" -> {
                val value = (call.argument<Any>("voice") as? Number)?.toInt()
                if (value == null || value < 0 || value > 4) {
                    result.error("BAD_VOICE", "Unknown voice effect", null)
                    return
                }
                val adapter = captureProcessing()
                if (adapter == null) {
                    result.error("NO_AUDIO", "Audio processing is unavailable", null)
                    return
                }
                val effect = voice ?: VoiceEffect().also { voice = it }
                if (audio !== adapter) {
                    audio?.removeProcessor(effect)
                    adapter.addProcessor(effect)
                    audio = adapter
                }
                effect.mode = value
            }
            "setMask" -> {
                val mask = call.argument<Any>("mask") as? String
                val trackId = call.argument<Any>("trackId") as? String
                val processor = masks ?: context?.let { MaskProcessor(it) }?.also { masks = it }
                if (mask == null || trackId == null || processor == null) {
                    result.error("BAD_MASK", "Unknown face mask", null)
                    return
                }
                var style: MaskStyle? = null
                if (mask != NO_MASK) {
                    style = catalog?.style(mask)
                    if (style == null) {
                        result.error("BAD_MASK", "Unknown face mask", mask)
                        return
                    }
                }
                val local = localTrack(trackId)
                if (local == null) {
                    result.error("NO_CAMERA", "Camera track is unavailable", null)
                    return
                }
                if (track !== local) {
                    track?.removeProcessor(processor)
                    processor.flush()
                    track = local
                    local.addProcessor(processor)
                }
                processor.style = style
            }
            "reset" -> reset()
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    private fun reset() {
        restoreBrightness()
        voice?.mode = 0
        val processor = masks
        if (processor != null) {
            track?.removeProcessor(processor)
            processor.reset()
        }
        track = null
        val effect = voice
        if (effect != null) audio?.removeProcessor(effect)
        audio = null
    }

    private fun captureProcessing(): AudioProcessingAdapter? = try {
        FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController?.capturePostProcessing
    } catch (error: NullPointerException) {
        null
    }

    private fun localTrack(trackId: String): LocalVideoTrack? = try {
        FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack
    } catch (error: NullPointerException) {
        null
    }

    private fun applyLight() {
        val level = lightBrightness ?: return
        val window = activity?.window ?: return
        if (litWindow !== window) {
            originalBrightness = window.attributes.screenBrightness
            litWindow = window
        }
        setBrightness(window, level)
    }

    private fun restoreBrightness() {
        lightBrightness = null
        val window = litWindow ?: return
        litWindow = null
        setBrightness(window, originalBrightness)
    }

    private fun detachActivity() {
        activity = null
        litWindow = null
    }

    private fun setBrightness(window: Window, value: Float) {
        val attributes = window.attributes
        attributes.screenBrightness = value
        window.attributes = attributes
    }

    companion object {
        private const val CHANNEL = "promax/effects"
        private const val NO_MASK = "none"
    }
}
