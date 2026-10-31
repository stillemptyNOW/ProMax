package promax.effects

import java.nio.ByteBuffer

internal object NativeEffects {
    const val SAMPLE_STRIDE = 9
    const val SPEC_SIZE = 8
    const val QUAD_STRIDE = 9
    const val FACE_CAPACITY = 2
    const val QUAD_CAPACITY = FACE_CAPACITY * 2

    init {
        System.loadLibrary("promax_effects")
    }

    @JvmStatic
    external fun maskAnchor(name: String): Int

    @JvmStatic
    external fun voiceCreate(): Long

    @JvmStatic
    external fun voiceDestroy(handle: Long)

    @JvmStatic
    external fun voiceProcess(handle: Long, mode: Int, rate: Int, buffer: ByteBuffer, frames: Int)

    @JvmStatic
    external fun trackerCreate(): Long

    @JvmStatic
    external fun trackerDestroy(handle: Long)

    @JvmStatic
    external fun trackerReset(handle: Long)

    @JvmStatic
    external fun trackerUpdate(handle: Long, samples: DoubleArray, count: Int, time: Double)

    @JvmStatic
    external fun trackerQuads(handle: Long, time: Double, spec: DoubleArray, out: DoubleArray): Int
}
