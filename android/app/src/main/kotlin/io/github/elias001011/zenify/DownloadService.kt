package io.github.elias001011.zenify

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

// Holds the process while songs download, so Android does not freeze the app
// in the background. The downloads themselves run in Dart; this only shows
// the progress notification and is stopped from Dart when they end.
class DownloadService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val notification = DownloadNotifications.progress(
      this,
      intent?.getStringExtra(EXTRA_TITLE) ?: "",
      intent?.getStringExtra(EXTRA_TEXT) ?: "",
      intent?.getIntExtra(EXTRA_MAX, 0) ?: 0,
      intent?.getIntExtra(EXTRA_CURRENT, 0) ?: 0,
    )
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
          DownloadNotifications.PROGRESS_ID,
          notification,
          ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
      } else {
        startForeground(DownloadNotifications.PROGRESS_ID, notification)
      }
    } catch (e: Exception) {
      // Android may refuse (ForegroundServiceStartNotAllowedException and
      // the like); the downloads go on without the service.
      Log.w(TAG, "Could not start the download service in the foreground", e)
      stopSelf()
    }
    // Not brought back after the process dies: the downloads would not be.
    return START_NOT_STICKY
  }

  // Android 15 ends a data sync service after a few hours.
  override fun onTimeout(startId: Int, fgsType: Int) {
    stopSelf()
  }

  companion object {
    private const val TAG = "DownloadService"
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_TEXT = "text"
    private const val EXTRA_MAX = "max"
    private const val EXTRA_CURRENT = "current"

    fun intent(context: Context, title: String, text: String, max: Int, current: Int) =
      Intent(context, DownloadService::class.java)
        .putExtra(EXTRA_TITLE, title)
        .putExtra(EXTRA_TEXT, text)
        .putExtra(EXTRA_MAX, max)
        .putExtra(EXTRA_CURRENT, current)
  }
}
