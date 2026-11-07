package com.yassine.yazen

import android.content.ContentResolver
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Decodes a local audio source and produces real, time-indexed spectrum frames.
 * This deliberately analyzes PCM from the file rather than relying on the
 * device's output Visualizer, which is unavailable or silent on some phones.
 */
class PcmSpectrumAnalyzer(
    private val contentResolver: ContentResolver,
    private val isCancelled: () -> Boolean,
) {
    private companion object {
        // 40 minutes at 40 ms/frame; keeps unusually long files bounded
        // without freezing ordinary long-form mixes or live recordings.
        const val MAX_FRAMES = 60000
    }
    data class Result(
        val frames: List<FloatArray>,
        val frameDurationMs: Long,
        val sampleRate: Int,
        val channels: Int,
    )

    fun analyze(
        uri: Uri,
        bandCount: Int = 40,
        onFrames: ((List<FloatArray>) -> Unit)? = null,
    ): Result? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var descriptor: ParcelFileDescriptor? = null
        try {
            descriptor = openExtractor(extractor, uri)
            var audioTrack = -1
            var format: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(index)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrack = index
                    format = candidate
                    break
                }
            }
            if (audioTrack < 0 || format == null) return null
            extractor.selectTrack(audioTrack)

            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val initialRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44100)
            val initialChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 1)
            val frames = ArrayList<FloatArray>()
            val pendingCallbacks = ArrayList<FloatArray>(32)
            var sampleRate = initialRate
            var channels = initialChannels
            var pcmEncoding = format.getInteger(
                MediaFormat.KEY_PCM_ENCODING,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val windowSize = 2048
            val hopSize = max(256, (sampleRate * 0.040).toInt())
            var pending = FloatArray(windowSize * 3)
            var pendingCount = 0
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false

            while (!outputDone && !isCancelled()) {
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = codec.getInputBuffer(inputIndex)
                        if (input == null) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            val sampleSize = extractor.readSampleData(input, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    sampleSize,
                                    extractor.sampleTime,
                                    0,
                                )
                                extractor.advance()
                            }
                        }
                    }
                }

                when (val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outputFormat = codec.outputFormat
                        sampleRate = outputFormat.getInteger(
                            MediaFormat.KEY_SAMPLE_RATE,
                            sampleRate,
                        )
                        channels = outputFormat.getInteger(
                            MediaFormat.KEY_CHANNEL_COUNT,
                            channels,
                        )
                        pcmEncoding = outputFormat.getInteger(
                            MediaFormat.KEY_PCM_ENCODING,
                            pcmEncoding,
                        )
                    }
                    else -> if (outputIndex >= 0) {
                        if (bufferInfo.size > 0) {
                            val output = codec.getOutputBuffer(outputIndex)
                            if (output != null) {
                                output.position(bufferInfo.offset)
                                output.limit(bufferInfo.offset + bufferInfo.size)
                                val pcm = output.slice().order(ByteOrder.LITTLE_ENDIAN)
                                val bytesPerChannel = when (pcmEncoding) {
                                    AudioFormat.ENCODING_PCM_FLOAT,
                                    AudioFormat.ENCODING_PCM_32BIT,
                                    -> 4
                                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
                                    AudioFormat.ENCODING_PCM_8BIT -> 1
                                    else -> 2
                                }
                                val bytesPerSample = bytesPerChannel * max(1, channels)
                                while (pcm.remaining() >= bytesPerSample) {
                                    if (pendingCount >= pending.size) {
                                        pending = pending.copyOf(pending.size * 2)
                                    }
                                    var mono = 0f
                                    repeat(max(1, channels)) {
                                        mono += readSample(pcm, pcmEncoding)
                                    }
                                    pending[pendingCount++] = mono / max(1, channels)

                                    while (pendingCount >= windowSize) {
                                        val frame = computeSpectrum(
                                            pending,
                                            windowSize,
                                            sampleRate,
                                            bandCount,
                                        )
                                        if (frames.size < MAX_FRAMES) frames += frame
                                        pendingCallbacks += frame
                                        if (pendingCallbacks.size >= 32) {
                                            onFrames?.invoke(pendingCallbacks.toList())
                                            pendingCallbacks.clear()
                                        }
                                        if (pendingCount == hopSize) {
                                            pendingCount = 0
                                        } else {
                                            System.arraycopy(
                                                pending,
                                                hopSize,
                                                pending,
                                                0,
                                                pendingCount - hopSize,
                                            )
                                            pendingCount -= hopSize
                                        }
                                    }
                                }
                            }
                        }
                        outputDone =
                            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
            if (pendingCallbacks.isNotEmpty() && !isCancelled()) {
                onFrames?.invoke(pendingCallbacks.toList())
            }
            if (isCancelled() || frames.isEmpty()) return null
            return Result(
                frames = frames,
                frameDurationMs = (hopSize * 1000L / max(1, sampleRate)),
                sampleRate = sampleRate,
                channels = channels,
            )
        } catch (_: Throwable) {
            return null
        } finally {
            try {
                codec?.stop()
            } catch (_: Throwable) {
                // Decoder may already have stopped after a device failure.
            }
            try {
                codec?.release()
            } catch (_: Throwable) {
                // Nothing else to release.
            }
            extractor.release()
            try {
                descriptor?.close()
            } catch (_: Throwable) {
                // The descriptor may already be closed by the provider.
            }
        }
    }

    private fun openExtractor(
        extractor: MediaExtractor,
        uri: Uri,
    ): ParcelFileDescriptor? {
        if (uri.scheme == "content") {
            val descriptor = contentResolver.openFileDescriptor(uri, "r")
                ?: throw IllegalStateException("Unable to open audio content URI")
            extractor.setDataSource(descriptor.fileDescriptor)
            return descriptor
        }
        val path = uri.path ?: throw IllegalArgumentException("Audio URI has no path")
        extractor.setDataSource(path)
        return null
    }

    private fun readSample(buffer: ByteBuffer, encoding: Int): Float {
        return when (encoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> buffer.float.coerceIn(-1f, 1f)
            AudioFormat.ENCODING_PCM_32BIT ->
                (buffer.int.toLong().toDouble() / 2147483648.0).toFloat()
            AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                val b0 = buffer.get().toInt() and 0xff
                val b1 = buffer.get().toInt() and 0xff
                val b2 = buffer.get().toInt()
                val value = b0 or (b1 shl 8) or (b2 shl 16)
                val signed = if ((value and 0x800000) != 0) value or -0x1000000 else value
                (signed / 8388608f).coerceIn(-1f, 1f)
            }
            AudioFormat.ENCODING_PCM_8BIT ->
                ((buffer.get().toInt() and 0xff) - 128) / 128f
            else -> buffer.short.toInt() / 32768f
        }
    }

    private fun computeSpectrum(
        source: FloatArray,
        size: Int,
        sampleRate: Int,
        bandCount: Int,
    ): FloatArray {
        val real = FloatArray(size)
        val imaginary = FloatArray(size)
        for (index in 0 until size) {
            val window = (0.5 - 0.5 * cos(2.0 * PI * index / (size - 1))).toFloat()
            real[index] = source[index] * window
        }
        fft(real, imaginary)

        val magnitudes = FloatArray(size / 2)
        for (index in magnitudes.indices) {
            val magnitude = sqrt(
                real[index].toDouble() * real[index].toDouble() +
                    imaginary[index].toDouble() * imaginary[index].toDouble(),
            ).toFloat() / size.toFloat() * 2f
            magnitudes[index] = magnitude
        }

        val output = FloatArray(bandCount)
        val nyquist = max(1000, sampleRate / 2)
        val minHz = 35.0
        val maxHz = min(20_000.0, nyquist.toDouble())
        for (band in 0 until bandCount) {
            val lowHz = minHz * (maxHz / minHz).pow(band.toDouble() / bandCount)
            val highHz = minHz * (maxHz / minHz).pow((band + 1).toDouble() / bandCount)
            val start = max(1, (lowHz * size / sampleRate).toInt())
            val end = min(magnitudes.lastIndex, max(start + 1, (highHz * size / sampleRate).toInt()))
            var sum = 0.0
            var peak = 0f
            var count = 0
            for (bin in start..end) {
                val value = magnitudes[bin]
                sum += value.toDouble() * value.toDouble()
                peak = max(peak, value)
                count++
            }
            val rms = sqrt(sum / max(1, count)).toFloat()
            val energy = max(rms * 1.18f, peak * 0.72f)
            val decibels = 20.0 * log10(max(energy.toDouble(), 0.000001))
            output[band] = ((decibels + 72.0) / 66.0).toFloat().coerceIn(0f, 1f)
        }
        return output
    }

    private fun fft(real: FloatArray, imaginary: FloatArray) {
        val size = real.size
        var j = 0
        for (i in 1 until size) {
            var bit = size shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val realValue = real[i]
                real[i] = real[j]
                real[j] = realValue
            }
        }

        var length = 2
        while (length <= size) {
            val angle = -2.0 * PI / length
            val wLengthReal = cos(angle).toFloat()
            val wLengthImaginary = sin(angle).toFloat()
            for (start in 0 until size step length) {
                var wReal = 1f
                var wImaginary = 0f
                val half = length / 2
                for (offset in 0 until half) {
                    val even = start + offset
                    val odd = even + half
                    val oddReal = real[odd] * wReal - imaginary[odd] * wImaginary
                    val oddImaginary = real[odd] * wImaginary + imaginary[odd] * wReal
                    val evenReal = real[even]
                    val evenImaginary = imaginary[even]
                    real[even] = evenReal + oddReal
                    imaginary[even] = evenImaginary + oddImaginary
                    real[odd] = evenReal - oddReal
                    imaginary[odd] = evenImaginary - oddImaginary
                    val nextWReal = wReal * wLengthReal - wImaginary * wLengthImaginary
                    wImaginary = wReal * wLengthImaginary + wImaginary * wLengthReal
                    wReal = nextWReal
                }
            }
            length = length shl 1
        }
    }

    private fun Double.pow(power: Double): Double = kotlin.math.exp(power * kotlin.math.ln(this))
}
