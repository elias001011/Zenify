package io.github.elias001011.zenify

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

// The notifications of downloads: one with the progress, which is also the
// one of the foreground service, and one with what failed.
object DownloadNotifications {
  const val PROGRESS_ID = 4201
  const val FAILURE_ID = 4202
  const val PROGRESS_CHANNEL = "zenify_downloads"
  const val FAILURE_CHANNEL = "zenify_download_failures"

  /// Set on the intent of a tap, to show the Downloads tab.
  const val EXTRA_OPEN_DOWNLOADS = "io.github.elias001011.zenify.OPEN_DOWNLOADS"

  fun canNotify(context: Context) = NotificationManagerCompat.from(context).areNotificationsEnabled()

  fun createChannels(context: Context, progressName: String, failureName: String) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
      NotificationChannel(PROGRESS_CHANNEL, progressName, NotificationManager.IMPORTANCE_LOW),
    )
    manager.createNotificationChannel(
      NotificationChannel(FAILURE_CHANNEL, failureName, NotificationManager.IMPORTANCE_LOW),
    )
  }

  fun progress(context: Context, title: String, text: String, max: Int, current: Int): Notification =
    NotificationCompat.Builder(context, PROGRESS_CHANNEL)
      .setSmallIcon(android.R.drawable.stat_sys_download)
      .setContentTitle(title)
      .setContentText(text)
      .setProgress(max, current, max <= 0)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setShowWhen(false)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .setContentIntent(openDownloads(context))
      .build()

  fun showProgress(context: Context, title: String, text: String, max: Int, current: Int) =
    post(context, PROGRESS_ID, progress(context, title, text, max, current))

  // Not ongoing: it stays after the downloads end, until it is dismissed.
  fun showFailures(context: Context, title: String, text: String) =
    post(
      context,
      FAILURE_ID,
      NotificationCompat.Builder(context, FAILURE_CHANNEL)
        .setSmallIcon(android.R.drawable.stat_notify_error)
        .setContentTitle(title)
        .setContentText(text)
        .setAutoCancel(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setCategory(NotificationCompat.CATEGORY_ERROR)
        .setContentIntent(openDownloads(context))
        .build(),
    )

  fun cancel(context: Context, id: Int) = NotificationManagerCompat.from(context).cancel(id)

  @SuppressLint("MissingPermission")
  private fun post(context: Context, id: Int, notification: Notification) {
    if (canNotify(context)) NotificationManagerCompat.from(context).notify(id, notification)
  }

  private fun openDownloads(context: Context): PendingIntent {
    val intent = Intent(context, MainActivity::class.java)
      .putExtra(EXTRA_OPEN_DOWNLOADS, true)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    return PendingIntent.getActivity(
      context,
      PROGRESS_ID,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}
