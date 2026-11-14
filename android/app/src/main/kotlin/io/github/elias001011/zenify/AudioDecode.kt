package io.github.elias001011.zenify

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioFormat
import android.os.SystemClock
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.nio.ByteOrder

// For the Mix's analysis: decodes a stretch of a song (a path or URL) to mono
// 16-bit PCM in a file, without playing it.
object AudioDecode {
  // Returns the sample rate of the file. A negative startMs counts from the end.
  fun decode(
    source: String,
    headers: Map<String, String>?,
    startMs: Long,
    lengthMs: Long,
    out: String,
  ): Int {
    require(lengthMs in 1..40_000) { "Invalid analysis length" }
    val extractor = MediaExtractor()
    var codec: MediaCodec? = null
    try {
      if (headers != null) extractor.setDataSource(source, headers) else extractor.setDataSource(source)
      val track = (0 until extractor.trackCount).first {
        extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
      }
      val format = extractor.getTrackFormat(track)
      extractor.selectTrack(track)
      val startUs = if (startMs < 0) {
        maxOf(0L, format.getLong(MediaFormat.KEY_DURATION) + startMs * 1000)
      } else {
        startMs * 1000
      }
      val endUs = startUs + lengthMs * 1000
      extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

      codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
      codec.configure(format, null, null, 0)
      codec.start()
      var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
      var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
      var encoding = AudioFormat.ENCODING_PCM_16BIT
      val info = MediaCodec.BufferInfo()
      var inputDone = false
      var outputDone = false
      val deadline = SystemClock.elapsedRealtime() + 45_000
      var groupSum = 0L
      var groupFrames = 0

      BufferedOutputStream(FileOutputStream(out)).use { file ->
        while (!outputDone) {
          check(SystemClock.elapsedRealtime() < deadline) { "Audio analysis timed out" }
          if (!inputDone) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) {
              val size = extractor.readSampleData(codec.getInputBuffer(index)!!, 0)
              if (size < 0 || extractor.sampleTime >= endUs) {
                codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                inputDone = true
              } else {
                codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                extractor.advance()
              }
            }
          }
          val index = codec.dequeueOutputBuffer(info, 10_000)
          if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
            rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            encoding = if (codec.outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
              codec.outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
            } else AudioFormat.ENCODING_PCM_16BIT
            check(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT) {
              "Unsupported PCM encoding"
            }
            groupSum = 0L
            groupFrames = 0
          } else if (index >= 0) {
            if (info.size > 0) {
              val buffer = codec.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
              buffer.position(info.offset)
              buffer.limit(info.offset + info.size)
              val bytesPerSample = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
              val frames = info.size / (bytesPerSample * channels)
              val every = maxOf(1, rate / 11025)
              val mono = ByteArray((frames / every + 1) * 2)
              var at = 0
              for (frame in 0 until frames) {
                var sum = 0L
                repeat(channels) {
                  sum += if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                    (buffer.float.coerceIn(-1f, 1f) * 32767).toLong()
                  } else buffer.short.toLong()
                }
                val timeUs = info.presentationTimeUs + frame * 1_000_000L / rate
                if (timeUs < startUs) continue
                if (timeUs >= endUs) {
                  outputDone = true
                  break
                }
                groupSum += sum
                groupFrames++
                // Carry the incomplete downsampling group across buffers:
                // discarding it on each buffer slowly shifts the beat grid.
                if (groupFrames == every) {
                  val value = (groupSum / (every * channels)).toInt()
                  mono[at++] = value.toByte()
                  mono[at++] = (value shr 8).toByte()
                  groupSum = 0L
                  groupFrames = 0
                }
              }
              file.write(mono, 0, at)
            }
            codec.releaseOutputBuffer(index, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
          }
        }
      }
      return rate / maxOf(1, rate / 11025)
    } finally {
      try { codec?.release() } finally { extractor.release() }
    }
  }
}
