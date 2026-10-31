package io.github.elias001011.zenify

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// The channel `zenify/downloads`: Dart starts and stops the download service,
// updates its notifications, and asks for the notification permission; this
// tells Dart when a tap on a notification should show the Downloads tab.
class DownloadChannel(private val activity: Activity) {
  private var channel: MethodChannel? = null
  private var pendingPermission: MethodChannel.Result? = null

  // A tap that Dart has not taken yet: the app was started by it.
  private var openRequested = false

  fun register(messenger: BinaryMessenger) {
    val channel = MethodChannel(messenger, "zenify/downloads")
    this.channel = channel
    val context = activity.applicationContext
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          DownloadNotifications.createChannels(
            context,
            call.argument<String>("channelName") ?: "",
            call.argument<String>("failureChannelName") ?: "",
          )
          try {
            ContextCompat.startForegroundService(
              context,
              DownloadService.intent(
                context,
                call.argument<String>("title") ?: "",
                call.argument<String>("text") ?: "",
                call.argument<Int>("max") ?: 0,
                call.argument<Int>("current") ?: 0,
              ),
            )
            result.success(null)
          } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException and the like.
            Log.w(TAG, "Could not start the download service", e)
            result.error("service_not_started", e.message, e.javaClass.name)
          }
        }
        "progress" -> {
          DownloadNotifications.showProgress(
            context,
            call.argument<String>("title") ?: "",
            call.argument<String>("text") ?: "",
            call.argument<Int>("max") ?: 0,
            call.argument<Int>("current") ?: 0,
          )
          result.success(null)
        }
        "failures" -> {
          DownloadNotifications.showFailures(
            context,
            call.argument<String>("title") ?: "",
            call.argument<String>("text") ?: "",
          )
          result.success(null)
        }
        "clearFailures" -> {
          DownloadNotifications.cancel(context, DownloadNotifications.FAILURE_ID)
          result.success(null)
        }
        "stop" -> {
          context.stopService(Intent(context, DownloadService::class.java))
          DownloadNotifications.cancel(context, DownloadNotifications.PROGRESS_ID)
          result.success(null)
        }
        "hasNotificationPermission" -> result.success(DownloadNotifications.canNotify(context))
        "requestNotificationPermission" -> requestNotificationPermission(result)
        "takeOpenRequest" -> {
          result.success(openRequested)
          openRequested = false
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun requestNotificationPermission(result: MethodChannel.Result) {
    if (DownloadNotifications.canNotify(activity) || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      result.success(DownloadNotifications.canNotify(activity))
      return
    }
    pendingPermission?.success(false)
    pendingPermission = result
    ActivityCompat.requestPermissions(
      activity,
      arrayOf(Manifest.permission.POST_NOTIFICATIONS),
      NOTIFICATION_PERMISSION_REQUEST,
    )
  }

  fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
    if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
    pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    pendingPermission = null
  }

  /// Called with the intent that started the activity and with each new one.
  /// Dart is told right away, and may also ask for it later when it was not
  /// listening yet (a cold start).
  fun onIntent(intent: Intent?) {
    val tap = intent ?: return
    if (!tap.getBooleanExtra(DownloadNotifications.EXTRA_OPEN_DOWNLOADS, false)) return
    // The activity may be recreated with the same intent.
    tap.removeExtra(DownloadNotifications.EXTRA_OPEN_DOWNLOADS)
    openRequested = true
    channel?.invokeMethod(
      "openDownloads",
      null,
      object : MethodChannel.Result {
        override fun success(result: Any?) {
          openRequested = false
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

        override fun notImplemented() {}
      },
    )
  }

  private companion object {
    const val TAG = "DownloadChannel"
    const val NOTIFICATION_PERMISSION_REQUEST = 4109
  }
}
