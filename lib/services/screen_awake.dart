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
import 'package:musify/utilities/platform_utils.dart';

/// A visible lyrics panel holds this until it leaves the tree. Overlapping
/// panels during a transition share one Android window flag.
class ScreenAwake {
  static const _channel = MethodChannel('zenify/display');
  static int _readers = 0;

  static VoidCallback acquire() {
    if (!isAndroidPlatform) return () {};
    if (_readers++ == 0) unawaited(_set(true));
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_readers == 0) unawaited(_set(false));
    };
  }

  static Future<void> _set(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('keepScreenAwake', enabled);
    } on PlatformException {
      // Lyrics remain usable when the platform cannot change the window flag.
    } on MissingPluginException {
      // Desktop builds and widget previews do not have this Android channel.
    }
  }
}
