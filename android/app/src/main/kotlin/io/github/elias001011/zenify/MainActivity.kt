package io.github.elias001011.zenify

import android.Manifest
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
  private var visualizer: Visualizer? = null
  private var pendingPermission: MethodChannel.Result? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    // Aligns the Flutter view vertically with the window.
    WindowCompat.setDecorFitsSystemWindows(getWindow(), false)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Disable the Android splash screen fade out animation to avoid
      // a flicker before the similar frame is drawn in Flutter.
      splashScreen.setOnExitAnimationListener { splashScreenView -> splashScreenView.remove() }
    }

    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger

    MethodChannel(messenger, "zenify/display").setMethodCallHandler { call, result ->
      if (call.method == "keepScreenAwake") {
        if (call.arguments == true) {
          window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
          window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(null)
      } else {
        result.notImplemented()
      }
    }

    // The player's waves follow the music through Android's Visualizer, which
    // needs the audio recording permission even to read Zenify's own output.
    // It is asked for only when the user chooses it.
    MethodChannel(messenger, "zenify/audio_levels").setMethodCallHandler { call, result ->
      when (call.method) {
        "hasPermission" -> result.success(hasAudioPermission())
        "requestPermission" -> {
          if (hasAudioPermission()) {
            result.success(true)
          } else {
            pendingPermission?.success(false)
            pendingPermission = result
            ActivityCompat.requestPermissions(
              this,
              arrayOf(Manifest.permission.RECORD_AUDIO),
              AUDIO_PERMISSION_REQUEST,
            )
          }
        }
        else -> result.notImplemented()
      }
    }

    EventChannel(messenger, "zenify/audio_levels/frames").setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
          try {
            startVisualizer((arguments as? Number)?.toInt() ?: 0, events)
          } catch (e: Exception) {
            stopVisualizer()
            events.error("unavailable", e.message, null)
          }
        }

        override fun onCancel(arguments: Any?) = stopVisualizer()
      },
    )
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == AUDIO_PERMISSION_REQUEST) {
      pendingPermission?.success(
        grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
      )
      pendingPermission = null
    }
  }

  override fun onDestroy() {
    stopVisualizer()
    super.onDestroy()
  }

  private fun hasAudioPermission() =
    ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED

  /// Sends [overall level, then the level of each band in BAND_EDGES_HZ] for
  /// every FFT capture: the same five bands the desktop measures with mpv.
  private fun startVisualizer(session: Int, events: EventChannel.EventSink) {
    stopVisualizer()
    val captureSize = minOf(1024, Visualizer.getCaptureSizeRange()[1])
    visualizer = Visualizer(session).apply {
      this.captureSize = captureSize
      val binHz = samplingRate / 1000.0 / captureSize
      setDataCaptureListener(
        object : Visualizer.OnDataCaptureListener {
          override fun onWaveFormDataCapture(v: Visualizer?, wave: ByteArray?, rate: Int) {}

          override fun onFftDataCapture(v: Visualizer?, fft: ByteArray?, rate: Int) {
            if (fft == null) return
            val bins = fft.size / 2
            val bandEnergy = DoubleArray(BAND_EDGES_HZ.size - 1)
            val bandBins = IntArray(BAND_EDGES_HZ.size - 1)
            var energy = 0.0
            var band = 0
            for (k in 1 until bins) {
              val re = fft[2 * k].toDouble()
              val im = fft[2 * k + 1].toDouble()
              val power = re * re + im * im
              energy += power
              val hz = k * binHz
              while (band < bandEnergy.size - 1 && hz >= BAND_EDGES_HZ[band + 1]) band++
              if (hz >= BAND_EDGES_HZ[0]) {
                bandEnergy[band] += power
                bandBins[band]++
              }
            }
            val levels = DoubleArray(bandEnergy.size + 1)
            levels[0] = sqrt(energy / bins) / 128.0
            for (b in bandEnergy.indices) {
              levels[b + 1] = if (bandBins[b] > 0) sqrt(bandEnergy[b] / bandBins[b]) / 128.0 else 0.0
            }
            events.success(levels)
          }
        },
        Visualizer.getMaxCaptureRate(),
        false,
        true,
      )
      enabled = true
    }
  }

  private fun stopVisualizer() {
    visualizer?.run {
      enabled = false
      release()
    }
    visualizer = null
  }

  private companion object {
    const val AUDIO_PERMISSION_REQUEST = 4108

    /// Sub-bass, bass, low mids, mids and treble, as on desktop.
    val BAND_EDGES_HZ = doubleArrayOf(20.0, 90.0, 280.0, 1000.0, 4000.0, 20000.0)
  }
}
