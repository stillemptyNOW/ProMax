package promax.effects

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.PowerManager
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class FaceTracker(context: Context) {
    private val lock = Any()
    private val handle = NativeEffects.trackerCreate()
    private val busy = AtomicBoolean(false)
    private val samples = DoubleArray(NativeEffects.SAMPLE_STRIDE * NativeEffects.FACE_CAPACITY)
    private val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    private val thermalListener: Any?
    private var detector: FaceDetector? = null
    private var executor: ExecutorService? = null
    private var generation = 0L
    private var closed = false

    @Volatile
    private var lastSubmit = -1.0

    @Volatile
    private var hot = false

    init {
        thermalListener = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && power != null) {
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                hot = status >= PowerManager.THERMAL_STATUS_SEVERE
            }
            power.addThermalStatusListener(listener)
            listener
        } else {
            null
        }
    }

    fun wants(time: Double): Boolean {
        if (busy.get()) return false
        val last = lastSubmit
        val interval = if (hot) HOT_INTERVAL else INTERVAL
        return last < 0 || time < last || time - last >= interval
    }

    fun submit(bitmap: Bitmap, uprightWidth: Int, uprightHeight: Int, time: Double) {
        if (uprightWidth <= 0 || uprightHeight <= 0) return
        if (!busy.compareAndSet(false, true)) return
        val client: FaceDetector
        val callbacks: ExecutorService
        val token: Long
        synchronized(lock) {
            if (closed) {
                busy.set(false)
                return
            }
            client = detector ?: FaceDetection.getClient(OPTIONS).also { detector = it }
            callbacks = executor ?: Executors.newSingleThreadExecutor().also { executor = it }
            token = generation
        }
        lastSubmit = time
        val unitsWidth = UNITS * uprightWidth / uprightHeight
        val imageWidth = bitmap.width.toDouble()
        val imageHeight = bitmap.height.toDouble()
        try {
            client.process(InputImage.fromBitmap(bitmap, 0)).addOnCompleteListener(callbacks) { task ->
                try {
                    if (task.isSuccessful) {
                        deliver(task.result, token, imageWidth, imageHeight, unitsWidth, time)
                    }
                } finally {
                    busy.set(false)
                }
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "Face detection failed", error)
            busy.set(false)
        }
    }

    fun quads(time: Double, spec: DoubleArray, out: DoubleArray): Int {
        synchronized(lock) {
            if (closed) return 0
            return NativeEffects.trackerQuads(handle, time, spec, out)
        }
    }

    fun reset() {
        synchronized(lock) {
            if (closed) return
            generation += 1
            NativeEffects.trackerReset(handle)
            lastSubmit = -1.0
        }
    }

    fun close() {
        val client: FaceDetector?
        val callbacks: ExecutorService?
        synchronized(lock) {
            if (closed) return
            closed = true
            generation += 1
            client = detector
            callbacks = executor
            detector = null
            executor = null
            NativeEffects.trackerDestroy(handle)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && power != null) {
            val listener = thermalListener as? PowerManager.OnThermalStatusChangedListener
            if (listener != null) power.removeThermalStatusListener(listener)
        }
        client?.close()
        callbacks?.shutdown()
    }

    private fun deliver(
        faces: List<Face>,
        token: Long,
        imageWidth: Double,
        imageHeight: Double,
        unitsWidth: Double,
        time: Double,
    ) {
        val ordered = faces.sortedByDescending { face ->
            face.boundingBox.width().toLong() * face.boundingBox.height().toLong()
        }
        var count = 0
        for (face in ordered) {
            if (count >= NativeEffects.FACE_CAPACITY) break
            val left = face.getLandmark(FaceLandmark.LEFT_EYE)?.position ?: continue
            val right = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position ?: continue
            val nose = face.getLandmark(FaceLandmark.NOSE_BASE)?.position ?: continue
            val mouthLeft = face.getLandmark(FaceLandmark.MOUTH_LEFT)?.position
            val mouthRight = face.getLandmark(FaceLandmark.MOUTH_RIGHT)?.position
            val mouthBottom = face.getLandmark(FaceLandmark.MOUTH_BOTTOM)?.position
            val mouthX: Double
            val mouthY: Double
            if (mouthLeft != null && mouthRight != null) {
                mouthX = (mouthLeft.x + mouthRight.x) / 2.0
                mouthY = (mouthLeft.y + mouthRight.y) / 2.0
            } else if (mouthBottom != null) {
                mouthX = mouthBottom.x.toDouble()
                mouthY = mouthBottom.y.toDouble()
            } else {
                continue
            }
            val base = count * NativeEffects.SAMPLE_STRIDE
            samples[base] = left.x / imageWidth * unitsWidth
            samples[base + 1] = (1.0 - left.y / imageHeight) * UNITS
            samples[base + 2] = right.x / imageWidth * unitsWidth
            samples[base + 3] = (1.0 - right.y / imageHeight) * UNITS
            samples[base + 4] = nose.x / imageWidth * unitsWidth
            samples[base + 5] = (1.0 - nose.y / imageHeight) * UNITS
            samples[base + 6] = mouthX / imageWidth * unitsWidth
            samples[base + 7] = (1.0 - mouthY / imageHeight) * UNITS
            samples[base + 8] = Math.toRadians(face.headEulerAngleX.toDouble())
            count += 1
        }
        synchronized(lock) {
            if (closed || generation != token) return
            NativeEffects.trackerUpdate(handle, samples, count, time)
        }
    }

    companion object {
        const val UNITS = 1000.0
        private const val TAG = "ProMaxEffects"
        private const val INTERVAL = 1.0 / 15
        private const val HOT_INTERVAL = 1.0 / 8
        private val OPTIONS: FaceDetectorOptions = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
            .setMinFaceSize(0.1f)
            .build()
    }
}
