package io.github.stillemptynow.promax

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors

object SubjectLift {

    private const val TAG = "SubjectLift"
    private const val CHANNEL = "io.github.stillemptynow.promax/sticker"
    private const val CACHE_DIR = "sticker_lift"
    private const val MAX_INPUT_SIDE = 1536

    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var segmenter: SubjectSegmenter? = null

    fun attach(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(available(app))
                    "lift" -> lift(app, call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun available(context: Context): Boolean =
        GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    @Synchronized
    private fun segmenter(): SubjectSegmenter =
        segmenter ?: SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder()
                .enableForegroundBitmap()
                .build(),
        ).also { segmenter = it }

    private fun lift(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty() || !available(context)) {
            result.success(null)
            return
        }
        executor.execute {
            try {
                val output = liftBlocking(context, path)
                handler.post { result.success(output) }
            } catch (e: ExecutionException) {
                val cause = e.cause
                if (cause is MlKitException && cause.errorCode == MlKitException.UNAVAILABLE) {
                    handler.post { result.error("downloading", cause.message, null) }
                } else {
                    Log.w(TAG, "subject lift failed: $e")
                    handler.post { result.success(null) }
                }
            } catch (e: Exception) {
                Log.w(TAG, "subject lift failed: $e")
                handler.post { result.success(null) }
            }
        }
    }

    private fun liftBlocking(context: Context, path: String): String? {
        val source = decode(path) ?: return null
        val segmentation = Tasks.await(segmenter().process(InputImage.fromBitmap(source, 0)))
        val foreground = segmentation.foregroundBitmap ?: return null
        val dir = File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, "lift_${System.currentTimeMillis()}.png")
        FileOutputStream(out).use { foreground.compress(Bitmap.CompressFormat.PNG, 100, it) }
        if (foreground !== source) foreground.recycle()
        source.recycle()
        return out.absolutePath
    }

    private fun decode(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_INPUT_SIDE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(path, options) ?: return null
        val degrees = try {
            when (
                ExifInterface(path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            ) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (e: Exception) {
            0f
        }
        if (degrees == 0f) return decoded
        val matrix = Matrix().apply { postRotate(degrees) }
        val rotated = Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height, matrix, true,
        )
        if (rotated !== decoded) decoded.recycle()
        return rotated
    }
}
