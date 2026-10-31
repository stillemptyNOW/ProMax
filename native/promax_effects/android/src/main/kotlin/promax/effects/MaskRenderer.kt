package promax.effects

import android.graphics.Bitmap
import android.graphics.Matrix
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import org.webrtc.GlRectDrawer
import org.webrtc.GlShader
import org.webrtc.GlTextureFrameBuffer
import org.webrtc.GlUtil
import org.webrtc.TextureBufferImpl
import org.webrtc.VideoFrame
import org.webrtc.VideoFrameDrawer
import org.webrtc.YuvConverter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal class MaskRenderer {
    private class Target(val buffer: GlTextureFrameBuffer) {
        val busy = AtomicBoolean(true)
    }

    private var context: EGLContext? = null
    @Volatile
    private var handler: Handler? = null
    private var frameDrawer: VideoFrameDrawer? = null
    private var cameraDrawer: GlRectDrawer? = null
    private var pixelDrawer: GlRectDrawer? = null
    private var converter: YuvConverter? = null
    private var maskShader: GlShader? = null
    private var detection: GlTextureFrameBuffer? = null
    private var pixels: GlTextureFrameBuffer? = null
    private val targets = ArrayList<Target>()
    private val textures = HashMap<String, Int>()
    private var readback: ByteBuffer? = null
    private var detectionImage: Bitmap? = null

    private val positions = floatBuffer(8)
    private val coordinates = floatBuffer(12)
    private val corners = DoubleArray(8)
    private val weights = DoubleArray(4)
    private val identity = FloatArray(16).also { android.opengl.Matrix.setIdentityM(it, 0) }
    private val upright = Array(4) { quarter -> rotationMatrix(-quarter * 90f, false) }
    private val flipped = rotationMatrix(0f, true)

    @Synchronized
    fun prepare(): Boolean {
        val current = EGL14.eglGetCurrentContext()
        if (current == null || current == EGL14.EGL_NO_CONTEXT) return false
        if (context != current) {
            forget()
            val looper = Looper.myLooper() ?: return false
            context = current
            handler = Handler(looper)
        }
        return true
    }

    @Synchronized
    fun detectionImage(frame: VideoFrame, limit: Int): Bitmap? {
        val handler = handler ?: return null
        if (handler.looper != Looper.myLooper()) return null
        val uprightWidth = frame.rotatedWidth
        val uprightHeight = frame.rotatedHeight
        if (uprightWidth <= 0 || uprightHeight <= 0) return null
        val scale = min(1.0, limit.toDouble() / max(uprightWidth, uprightHeight))
        val width = max(MIN_DETECTION, (uprightWidth * scale).roundToInt())
        val height = max(MIN_DETECTION, (uprightHeight * scale).roundToInt())
        val target = detection ?: GlTextureFrameBuffer(GLES20.GL_RGBA).also { detection = it }
        target.setSize(width, height)
        val (drawer, camera) = drawers()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, target.frameBufferId)
        drawer.drawFrame(frame, camera, flipped, 0, 0, width, height)
        val bytes = width * height * 4
        val buffer = readback?.takeIf { it.capacity() >= bytes }
            ?: ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder()).also { readback = it }
        buffer.clear()
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        val image = detectionImage?.takeIf { it.width == width && it.height == height }
            ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { detectionImage = it }
        buffer.position(0)
        buffer.limit(bytes)
        image.copyPixelsFromBuffer(buffer)
        return image
    }

    @Synchronized
    fun render(
        frame: VideoFrame,
        style: MaskStyle,
        quads: DoubleArray,
        count: Int,
        units: Double,
    ): VideoFrame? {
        val handler = handler ?: return null
        if (handler.looper != Looper.myLooper()) return null
        val width = frame.buffer.width
        val height = frame.buffer.height
        if (width <= 0 || height <= 0) return null
        val rotation = quarter(frame.rotation)
        val texture = if (style.pixelate) 0 else maskTexture(style)
        if (!style.pixelate && texture == 0) return null
        val target = acquire(width, height) ?: return null
        try {
            val (drawer, camera) = drawers()
            val unrotate = upright[rotation]
            var columns = 0
            var rows = 0
            if (style.pixelate) {
                val block = max(24.0, min(width, height) / 18.0)
                columns = max(1, ceil(width / block).toInt())
                rows = max(1, ceil(height / block).toInt())
                val grid = pixels ?: GlTextureFrameBuffer(GLES20.GL_RGBA).also { pixels = it }
                grid.setSize(columns, rows)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, grid.textureId)
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
                GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, grid.frameBufferId)
                drawer.drawFrame(frame, camera, unrotate, 0, 0, columns, rows)
            }
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, target.buffer.frameBufferId)
            drawer.drawFrame(frame, camera, unrotate, 0, 0, width, height)
            val scale = (if (rotation % 2 == 0) height else width) / units
            if (style.pixelate) {
                drawPixels(count, quads, scale, rotation, width, height, columns, rows)
            } else {
                drawMasks(texture, count, quads, scale, rotation, width, height)
            }
            GLES20.glFinish()
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            val output = TextureBufferImpl(
                width,
                height,
                VideoFrame.TextureBuffer.Type.RGB,
                target.buffer.textureId,
                Matrix(),
                handler,
                converter(),
                Runnable { target.busy.set(false) },
            )
            return VideoFrame(output, frame.rotation, frame.timestampNs)
        } catch (error: RuntimeException) {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            target.busy.set(false)
            throw error
        }
    }

    @Synchronized
    fun release() {
        if (context == null) return
        if (EGL14.eglGetCurrentContext() != context) {
            forget()
            return
        }
        frameDrawer?.release()
        cameraDrawer?.release()
        pixelDrawer?.release()
        maskShader?.release()
        detection?.release()
        pixels?.release()
        val idle = targets.filter { !it.busy.get() }
        idle.forEach { it.buffer.release() }
        if (textures.isNotEmpty()) {
            GLES20.glDeleteTextures(textures.size, textures.values.toIntArray(), 0)
        }
        forget()
    }

    fun post(action: Runnable): Boolean = handler?.post(action) ?: false

    private fun forget() {
        context = null
        handler = null
        frameDrawer = null
        cameraDrawer = null
        pixelDrawer = null
        converter = null
        maskShader = null
        detection = null
        pixels = null
        targets.clear()
        textures.clear()
    }

    private fun drawers(): Pair<VideoFrameDrawer, GlRectDrawer> {
        val drawer = frameDrawer ?: VideoFrameDrawer().also { frameDrawer = it }
        val camera = cameraDrawer ?: GlRectDrawer().also { cameraDrawer = it }
        return drawer to camera
    }

    private fun converter(): YuvConverter = converter ?: YuvConverter().also { converter = it }

    private fun acquire(width: Int, height: Int): Target? {
        val iterator = targets.iterator()
        while (iterator.hasNext()) {
            val target = iterator.next()
            val buffer = target.buffer
            if ((buffer.width != width || buffer.height != height) && target.busy.compareAndSet(false, true)) {
                buffer.release()
                iterator.remove()
            }
        }
        for (target in targets) {
            if (target.busy.compareAndSet(false, true)) return target
        }
        if (targets.size >= MAX_TARGETS) return null
        val buffer = GlTextureFrameBuffer(GLES20.GL_RGBA)
        buffer.setSize(width, height)
        val target = Target(buffer)
        targets.add(target)
        return target
    }

    private fun maskTexture(style: MaskStyle): Int {
        textures[style.id]?.let { return it }
        val image = style.image ?: return 0
        val pixels = ByteBuffer.allocateDirect(image.byteCount).order(ByteOrder.nativeOrder())
        image.copyPixelsToBuffer(pixels)
        pixels.position(0)
        val texture = GlUtil.generateTexture(GLES20.GL_TEXTURE_2D)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 4)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D,
            0,
            GLES20.GL_RGBA,
            image.width,
            image.height,
            0,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            pixels,
        )
        GLES20.glGenerateMipmap(GLES20.GL_TEXTURE_2D)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR_MIPMAP_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        textures[style.id] = texture
        return texture
    }

    private fun shader(): GlShader = maskShader ?: GlShader(MASK_VERTEX, MASK_FRAGMENT).also { maskShader = it }

    private fun drawMasks(
        texture: Int,
        count: Int,
        quads: DoubleArray,
        scale: Double,
        rotation: Int,
        width: Int,
        height: Int,
    ) {
        if (count <= 0) return
        val shader = shader()
        shader.useProgram()
        val alphaLocation = shader.getUniformLocation("alpha")
        GLES20.glUniform1i(shader.getUniformLocation("tex"), 0)
        GLES20.glViewport(0, 0, width, height)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        for (index in 0 until count) {
            val base = index * NativeEffects.QUAD_STRIDE
            val alpha = quads[base + 8]
            if (!(alpha > 0.001)) continue
            if (!place(quads, base, scale, rotation, width, height)) continue
            projectiveWeights()
            for (corner in 0 until 4) {
                val vertex = STRIP[corner]
                positions.put(corner * 2, (corners[vertex * 2] / width * 2 - 1).toFloat())
                positions.put(corner * 2 + 1, (corners[vertex * 2 + 1] / height * 2 - 1).toFloat())
                val weight = weights[vertex].toFloat()
                coordinates.put(corner * 3, TEXTURE_S[vertex] * weight)
                coordinates.put(corner * 3 + 1, TEXTURE_T[vertex] * weight)
                coordinates.put(corner * 3 + 2, weight)
            }
            positions.position(0)
            coordinates.position(0)
            shader.setVertexAttribArray("in_pos", 2, positions)
            shader.setVertexAttribArray("in_tc", 3, coordinates)
            GLES20.glUniform1f(alphaLocation, min(alpha, 1.0).toFloat())
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        GLES20.glDisableVertexAttribArray(shader.getAttribLocation("in_pos"))
        GLES20.glDisableVertexAttribArray(shader.getAttribLocation("in_tc"))
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun drawPixels(
        count: Int,
        quads: DoubleArray,
        scale: Double,
        rotation: Int,
        width: Int,
        height: Int,
        columns: Int,
        rows: Int,
    ) {
        val grid = pixels ?: return
        val drawer = pixelDrawer ?: GlRectDrawer().also { pixelDrawer = it }
        if (count <= 0) {
            drawer.drawRgb(grid.textureId, identity, columns, rows, 0, 0, width, height)
            return
        }
        GLES20.glEnable(GLES20.GL_SCISSOR_TEST)
        for (index in 0 until count) {
            val base = index * NativeEffects.QUAD_STRIDE
            if (!place(quads, base, scale, rotation, width, height)) continue
            var left = Double.MAX_VALUE
            var right = -Double.MAX_VALUE
            var bottom = Double.MAX_VALUE
            var top = -Double.MAX_VALUE
            for (corner in 0 until 4) {
                left = min(left, corners[corner * 2])
                right = max(right, corners[corner * 2])
                bottom = min(bottom, corners[corner * 2 + 1])
                top = max(top, corners[corner * 2 + 1])
            }
            val x0 = floor(left).toInt().coerceIn(0, width)
            val x1 = ceil(right).toInt().coerceIn(0, width)
            val y0 = floor(bottom).toInt().coerceIn(0, height)
            val y1 = ceil(top).toInt().coerceIn(0, height)
            if (x1 <= x0 || y1 <= y0) continue
            GLES20.glScissor(x0, y0, x1 - x0, y1 - y0)
            drawer.drawRgb(grid.textureId, identity, columns, rows, 0, 0, width, height)
        }
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST)
    }

    private fun place(quads: DoubleArray, base: Int, scale: Double, rotation: Int, width: Int, height: Int): Boolean {
        for (corner in 0 until 4) {
            val u = quads[base + corner * 2] * scale
            val v = quads[base + corner * 2 + 1] * scale
            if (!u.isFinite() || !v.isFinite()) return false
            val x: Double
            val y: Double
            when (rotation) {
                1 -> {
                    x = width - v
                    y = u
                }
                2 -> {
                    x = width - u
                    y = height - v
                }
                3 -> {
                    x = v
                    y = height - u
                }
                else -> {
                    x = u
                    y = v
                }
            }
            corners[corner * 2] = x
            corners[corner * 2 + 1] = y
        }
        return true
    }

    private fun projectiveWeights() {
        weights.fill(1.0)
        val x0 = corners[0]
        val y0 = corners[1]
        val x1 = corners[2]
        val y1 = corners[3]
        val x2 = corners[4]
        val y2 = corners[5]
        val x3 = corners[6]
        val y3 = corners[7]
        val ax = x2 - x0
        val ay = y2 - y0
        val bx = x3 - x1
        val by = y3 - y1
        val denominator = ax * by - ay * bx
        if (abs(denominator) < 1e-9) return
        val s = ((x1 - x0) * by - (y1 - y0) * bx) / denominator
        val t = ((x1 - x0) * ay - (y1 - y0) * ax) / denominator
        if (s <= 0 || s >= 1 || t <= 0 || t >= 1) return
        val cx = x0 + s * ax
        val cy = y0 + s * ay
        val d0 = hypot(x0 - cx, y0 - cy)
        val d1 = hypot(x1 - cx, y1 - cy)
        val d2 = hypot(x2 - cx, y2 - cy)
        val d3 = hypot(x3 - cx, y3 - cy)
        if (d0 <= 0 || d1 <= 0 || d2 <= 0 || d3 <= 0) return
        weights[0] = (d0 + d2) / d2
        weights[1] = (d1 + d3) / d3
        weights[2] = (d2 + d0) / d0
        weights[3] = (d3 + d1) / d1
    }

    private fun quarter(rotation: Int): Int = (((rotation / 90) % 4) + 4) % 4

    companion object {
        private const val MAX_TARGETS = 6
        private const val MIN_DETECTION = 32
        private val STRIP = intArrayOf(0, 1, 3, 2)
        private val TEXTURE_S = floatArrayOf(0f, 1f, 1f, 0f)
        private val TEXTURE_T = floatArrayOf(0f, 0f, 1f, 1f)

        private const val MASK_VERTEX = """
attribute vec4 in_pos;
attribute vec3 in_tc;
varying vec3 tc;
void main() {
  gl_Position = in_pos;
  tc = in_tc;
}
"""

        private const val MASK_FRAGMENT = """
precision mediump float;
varying vec3 tc;
uniform sampler2D tex;
uniform float alpha;
void main() {
  gl_FragColor = texture2D(tex, tc.xy / tc.z) * alpha;
}
"""

        private fun floatBuffer(size: Int): FloatBuffer =
            ByteBuffer.allocateDirect(size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

        private fun rotationMatrix(degrees: Float, flip: Boolean): Matrix = Matrix().apply {
            preTranslate(0.5f, 0.5f)
            if (flip) preScale(1f, -1f)
            preRotate(degrees)
            preTranslate(-0.5f, -0.5f)
        }
    }
}
