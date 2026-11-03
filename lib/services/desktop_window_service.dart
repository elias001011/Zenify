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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:window_manager/window_manager.dart';

/// The native window around the Flutter view, through the `musify/window`
/// channel of the Linux and Windows runners.
class DesktopWindow {
  DesktopWindow._();

  static const _channel = MethodChannel('musify/window');

  static String? _lastTitleBarTheme;
  static final clientTitleBarActive = ValueNotifier<bool>(false);
  static bool roundedFrameSupported = false;
  static Future<void>? _chromeOperation;
  static bool? _requestedClientTitleBar;
  static bool _windowManagerReady = false;

  /// Native controls are replaced only after the platform confirms that the
  /// caption is hidden. Unsupported hosts keep their existing title bar.
  static Future<void> configureClientTitleBar(bool enabled) {
    if (!isDesktopPlatform || defaultTargetPlatform == TargetPlatform.macOS) {
      return Future.value();
    }
    if (_requestedClientTitleBar == enabled)
      return _chromeOperation ?? Future.value();
    final firstRequest = _requestedClientTitleBar == null;
    _requestedClientTitleBar = enabled;
    if (!enabled && !_windowManagerReady && firstRequest) return Future.value();
    final operation = (_chromeOperation ?? Future<void>.value()).then((
      _,
    ) async {
      var captionChanged = false;
      try {
        if (!_windowManagerReady) {
          await windowManager.ensureInitialized();
          _windowManagerReady = true;
        }
        await windowManager.setTitleBarStyle(
          enabled ? TitleBarStyle.hidden : TitleBarStyle.normal,
          windowButtonVisibility: !enabled,
        );
        captionChanged = true;
        try {
          roundedFrameSupported =
              await _channel.invokeMethod<bool>('setClientFrame', {
                'enabled': enabled,
              }) ??
              false;
        } on MissingPluginException {
          roundedFrameSupported = false;
        }
        clientTitleBarActive.value = enabled;
      } catch (error, stackTrace) {
        logger.log(
          'Could not change the title bar',
          error: error,
          stackTrace: stackTrace,
        );
        if (_requestedClientTitleBar == enabled)
          _requestedClientTitleBar = null;
        if (!captionChanged) return;
        if (!enabled) {
          clientTitleBarActive.value = false;
          roundedFrameSupported = false;
          return;
        }
        // A partial failure must restore native controls before discarding ours.
        try {
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          clientTitleBarActive.value = false;
          roundedFrameSupported = false;
        } catch (rollbackError, rollbackStack) {
          logger.log(
            'Could not restore the native title bar',
            error: rollbackError,
            stackTrace: rollbackStack,
          );
          clientTitleBarActive.value = true;
        }
      }
    });
    _chromeOperation = operation;
    unawaited(
      operation.then((_) {
        if (identical(_chromeOperation, operation)) _chromeOperation = null;
      }),
    );
    return operation;
  }

  /// Before the first frame, so the window opens maximized instead of jumping.
  static Future<void> maximize() => _invoke('maximize');

  static Future<void> raise() => _invoke('raise');

  static void syncTitleBar(ThemeData theme) {
    final background = theme.scaffoldBackgroundColor.toARGB32();
    final foreground = theme.colorScheme.onSurface.toARGB32();
    final dark = theme.brightness == Brightness.dark;

    final key = '$dark:$background:$foreground';
    if (key == _lastTitleBarTheme) return;
    _lastTitleBarTheme = key;

    unawaited(
      _invoke('setTitleBarTheme', {
        'dark': dark,
        'background': background,
        'foreground': foreground,
      }),
    );
  }

  /// System colours, still in the system's light or dark mode.
  static void resetTitleBar({required bool dark}) {
    final key = 'system:$dark';
    if (key == _lastTitleBarTheme) return;
    _lastTitleBarTheme = key;
    unawaited(_invoke('resetTitleBarTheme', {'dark': dark}));
  }

  static Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // macOS and tests have no window channel.
    } on PlatformException catch (e, stackTrace) {
      logger.log(
        'Window call $method failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Extends each route's own canvas under transparent window controls. Page
/// content reserves the caption height; its background still fills the window.
class DesktopTitleBarTheme extends StatefulWidget {
  const DesktopTitleBarTheme({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopTitleBarTheme> createState() => _DesktopTitleBarThemeState();
}

class _DesktopTitleBarThemeState extends State<DesktopTitleBarTheme>
    with WindowListener {
  final _contentKey = GlobalKey();
  bool _maximized = false;
  bool _fullScreen = false;
  static const _height = 44.0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    customTitleBar.addListener(_configureTitleBar);
    _configureTitleBar();
    DesktopWindow.clientTitleBarActive.addListener(_readWindowState);
    _readWindowState();
  }

  void _configureTitleBar() =>
      unawaited(DesktopWindow.configureClientTitleBar(customTitleBar.value));

  void _readWindowState() {
    if (!DesktopWindow.clientTitleBarActive.value) return;
    unawaited(() async {
      try {
        final state = await Future.wait([
          windowManager.isMaximized(),
          windowManager.isFullScreen(),
        ]);
        if (mounted)
          setState(() {
            _maximized = state[0];
            _fullScreen = state[1];
          });
      } on MissingPluginException {
        // Unsupported hosts retain the native frame.
      } on PlatformException catch (error, stackTrace) {
        logger.log(
          'Could not read window state',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);
  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  @override
  void dispose() {
    DesktopWindow.clientTitleBarActive.removeListener(_readWindowState);
    windowManager.removeListener(this);
    customTitleBar.removeListener(_configureTitleBar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: customTitleBar,
    child: KeyedSubtree(key: _contentKey, child: widget.child),
    builder: (context, enabled, child) {
      if (enabled) {
        DesktopWindow.syncTitleBar(Theme.of(context));
      } else {
        DesktopWindow.resetTitleBar(
          dark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        );
      }
      return ValueListenableBuilder<bool>(
        valueListenable: DesktopWindow.clientTitleBarActive,
        child: child,
        builder: (context, integrated, child) {
          if (!integrated) return child!;
          final media = MediaQuery.of(context);
          final height = _fullScreen ? 0.0 : _height;
          return DragToResizeArea(
            resizeEdgeSize: 4,
            enableResizeEdges: _maximized || _fullScreen ? const [] : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                DesktopWindow.roundedFrameSupported &&
                        !_maximized &&
                        !_fullScreen
                    ? 12
                    : 0,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaQuery(
                    data: media.copyWith(
                      padding: media.padding.copyWith(
                        top: media.padding.top + height,
                      ),
                      viewPadding: media.viewPadding.copyWith(
                        top: media.viewPadding.top + height,
                      ),
                    ),
                    child: child!,
                  ),
                  if (!_fullScreen) ...[
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: height,
                      child: DragToMoveArea(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              appName,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 8,
                      height: 32,
                      child: DesktopCaptionControls(maximized: _maximized),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Native window actions in a small floating capsule, sharing platform behavior.
class DesktopCaptionControls extends StatelessWidget {
  const DesktopCaptionControls({super.key, required this.maximized});
  final bool maximized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget button(String label, Widget child) => Semantics(
      label: label,
      button: true,
      child: SizedBox(width: 32, height: 32, child: child),
    );
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            context.l10n!.windowMinimize,
            WindowCaptionButton.minimize(
              brightness: colors.brightness,
              onPressed: windowManager.minimize,
            ),
          ),
          button(
            maximized
                ? context.l10n!.windowRestore
                : context.l10n!.windowMaximize,
            maximized
                ? WindowCaptionButton.unmaximize(
                    brightness: colors.brightness,
                    onPressed: windowManager.unmaximize,
                  )
                : WindowCaptionButton.maximize(
                    brightness: colors.brightness,
                    onPressed: windowManager.maximize,
                  ),
          ),
          button(
            MaterialLocalizations.of(context).closeButtonTooltip,
            WindowCaptionButton.close(
              brightness: colors.brightness,
              onPressed: windowManager.close,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zooms the whole interface by [interfaceScale], like a browser zoom: the app
/// is laid out at a smaller or larger logical size and scaled to the window.
class DesktopInterfaceScale extends StatelessWidget {
  const DesktopInterfaceScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: interfaceScale,
      builder: (context, scale, child) {
        if (scale == 1) return child!;
        final media = MediaQuery.of(context);
        // Sized from the space actually given, not the window: a mismatch
        // would scale width and height differently and stretch everything.
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest / scale;
            return FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: MediaQuery(
                  data: media.copyWith(
                    size: size,
                    devicePixelRatio: media.devicePixelRatio * scale,
                    padding: media.padding / scale,
                    viewPadding: media.viewPadding / scale,
                    viewInsets: media.viewInsets / scale,
                  ),
                  child: child!,
                ),
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}
