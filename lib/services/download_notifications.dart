/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Keeps downloads running while the app is in the background, and shows
/// how they go, on Android: a foreground service with a progress
/// notification while a batch of downloads lasts, and a notification of
/// what failed. Tapping either opens the Downloads tab. Elsewhere it does
/// nothing. The native half is DownloadChannel.kt.
class DownloadNotifications {
  DownloadNotifications(
    this._manager, {
    this._channel = const MethodChannel('zenify/downloads'),
    AppLocalizations Function()? strings,
  }) : _strings = strings ?? (() => lookupAppLocalizations(languageSetting));

  static final instance = DownloadNotifications(DownloadManager.instance);

  static const _askedKey = 'notificationPermissionAsked';

  /// Android drops notification updates that come too fast.
  @visibleForTesting
  var updateInterval = const Duration(seconds: 1);

  final DownloadManager _manager;
  final MethodChannel _channel;
  final AppLocalizations Function() _strings;
  late final VoidCallback _openDownloads;
  var _attached = false;

  // Whether a batch holds the service, and whether the progress is shown:
  // not when Android refused the service, but the downloads go on.
  var _running = false;
  var _showing = false;
  var _failedShown = 0;
  var _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _update;

  /// Starts following the downloads. [openDownloads] shows the Downloads tab,
  /// when a notification is tapped.
  void attach({required VoidCallback openDownloads}) {
    if (!isAndroidPlatform || _attached) return;
    _attached = true;
    _openDownloads = openDownloads;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDownloads') unawaited(_open());
      return null;
    });
    _manager.progress.addListener(_onProgress);
    _manager.idle.addListener(_onIdle);
    _manager.batch.addListener(_onBatch);
    unawaited(_openIfLaunchedByTap());
  }

  @visibleForTesting
  void detach() {
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
    _manager.progress.removeListener(_onProgress);
    _manager.idle.removeListener(_onIdle);
    _manager.batch.removeListener(_onBatch);
    _update?.cancel();
    _update = null;
  }

  // The app was started by a tap, before this could listen for it.
  Future<void> _openIfLaunchedByTap() async {
    try {
      if (await _channel.invokeMethod<bool>('takeOpenRequest') ?? false) {
        await _open();
      }
    } on PlatformException {
      // The tab is one tap away.
    } on MissingPluginException {
      // Widget previews do not have this Android channel.
    }
  }

  // Once the first frame is there for the router to show the tab in.
  Future<void> _open() async {
    await WidgetsBinding.instance.endOfFrame;
    _openDownloads();
  }

  void _onProgress() {
    final progress = _manager.progress.value;
    if (progress.total == 0) return;
    if (!_running) {
      _running = true;
      unawaited(_begin(progress));
    } else if (_showing) {
      _scheduleUpdate();
    }
  }

  Future<void> _begin(BatchProgress progress) async {
    // The last batch's failures were told; a new one starts afresh.
    _failedShown = 0;
    unawaited(_invoke('clearFailures'));
    _lastSent = DateTime.now();
    unawaited(_askPermission());
    final strings = _strings();
    try {
      await _channel.invokeMethod<void>('start', {
        'channelName': strings.downloads,
        'failureChannelName': strings.downloadFailuresChannel,
        ..._progressArguments(strings, progress),
      });
      _showing = true;
      // The batch may have moved on while the service was starting.
      if (_running) _scheduleUpdate();
    } on PlatformException catch (error, stackTrace) {
      logger.log(
        'The download service did not start; downloads go on without it',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException {
      // Widget previews do not have this Android channel.
    }
  }

  // Asked for once, when the first download starts: the downloads do not wait
  // for the answer, and without it only the notification is missing.
  Future<void> _askPermission() async {
    try {
      final box = Hive.box('userNoBackup');
      if (box.get(_askedKey, defaultValue: false) == true) return;
      if (await _channel.invokeMethod<bool>('hasNotificationPermission') ??
          true) {
        return;
      }
      await box.put(_askedKey, true);
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } on PlatformException catch (error, stackTrace) {
      logger.log(
        'Could not ask for the notification permission',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException {
      // Widget previews do not have this Android channel.
    }
  }

  Map<String, Object> _progressArguments(
    AppLocalizations strings,
    BatchProgress progress,
  ) => {
    'title': strings.downloadsNotificationTitle,
    'text': strings.downloadsNotificationProgress(
      progress.done,
      progress.total,
    ),
    'max': progress.total,
    // Failed songs are over too, or the bar would never fill.
    'current': progress.done + progress.failed,
  };

  // At most one update per interval; the last state always follows.
  void _scheduleUpdate() {
    if (_update != null) return;
    final wait = updateInterval - DateTime.now().difference(_lastSent);
    _update = Timer(wait.isNegative ? Duration.zero : wait, _sendUpdate);
  }

  void _sendUpdate() {
    _update = null;
    if (!_running) return;
    _lastSent = DateTime.now();
    final progress = _manager.progress.value;
    final strings = _strings();
    unawaited(_invoke('progress', _progressArguments(strings, progress)));
    if (progress.failed != _failedShown) {
      _failedShown = progress.failed;
      unawaited(
        progress.failed == 0
            ? _invoke('clearFailures')
            : _invoke('failures', {
                'title': strings.downloadFailuresTitle,
                'text': strings.downloadFailuresCount(progress.failed),
              }),
      );
    }
  }

  void _onIdle() {
    if (!_manager.idle.value || !_running) return;
    _running = false;
    _showing = false;
    _update?.cancel();
    _update = null;
    unawaited(_invoke('stop'));
  }

  // The end of a batch with failures: what is left in the notification.
  void _onBatch() {
    final batch = _manager.batch.value;
    if (batch == null) return;
    final strings = _strings();
    _failedShown = batch.failed;
    unawaited(
      _invoke('failures', {
        'title': strings.downloadFailuresTitle,
        'text': batch.unavailable > 0
            ? strings.downloadFailuresUnavailable(
                batch.failed,
                batch.unavailable,
              )
            : strings.downloadFailuresCount(batch.failed),
      }),
    );
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error, stackTrace) {
      logger.log(
        'Download notification "$method" failed',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException {
      // Widget previews do not have this Android channel.
    }
  }
}
