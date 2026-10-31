package promax.effects

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer

internal class VoiceEffect : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private val handle = NativeEffects.voiceCreate()

    @Volatile
    var mode = 0

    override fun initialize(sampleRateHz: Int, numChannels: Int) = Unit

    override fun reset(newRate: Int) = Unit

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (handle == 0L || numFrames <= 0 || !buffer.isDirect) return
        NativeEffects.voiceProcess(handle, mode, numFrames * 100, buffer, numFrames)
    }

    fun release() {
        if (handle != 0L) NativeEffects.voiceDestroy(handle)
    }
}
