package promax.effects

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.VideoFrame
import java.util.concurrent.atomic.AtomicReference

internal class MaskProcessor(context: Context) : LocalVideoTrack.ExternalVideoFrameProcessing {
    private val tracker = FaceTracker(context)
    private val renderer = MaskRenderer()
    private val quads = DoubleArray(NativeEffects.QUAD_CAPACITY * NativeEffects.QUAD_STRIDE)
    private val pending = AtomicReference<VideoFrame?>(null)

    @Volatile
    var style: MaskStyle? = null

    override fun onFrame(frame: VideoFrame): VideoFrame {
        pending.getAndSet(null)?.release()
        val current = style ?: return frame
        return try {
            process(frame, current)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Face mask frame failed", error)
            frame
        }
    }

    fun flush() {
        pending.getAndSet(null)?.release()
    }

    fun reset() {
        style = null
        tracker.reset()
        flush()
        renderer.post { renderer.release() }
    }

    fun close() {
        reset()
        tracker.close()
    }

    private fun process(frame: VideoFrame, style: MaskStyle): VideoFrame {
        if (!renderer.prepare()) return frame
        val time = frame.timestampNs * 1e-9
        val uprightWidth = frame.rotatedWidth
        val uprightHeight = frame.rotatedHeight
        if (uprightWidth <= 0 || uprightHeight <= 0) return frame
        if (tracker.wants(time)) {
            val image = renderer.detectionImage(frame, DETECTION_LIMIT)
            if (image != null) tracker.submit(image, uprightWidth, uprightHeight, time)
        }
        val count = tracker.quads(time, style.spec, quads)
        if (count == 0 && !style.pixelate) return frame
        val output = renderer.render(frame, style, quads, count, FaceTracker.UNITS) ?: return frame
        pending.getAndSet(output)?.release()
        return output
    }

    companion object {
        private const val TAG = "ProMaxEffects"
        private const val DETECTION_LIMIT = 480
    }
}
