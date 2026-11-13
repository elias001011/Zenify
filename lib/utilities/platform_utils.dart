import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isIosPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isMobilePlatform => isAndroidPlatform || isIosPlatform;

bool get isLinuxPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

bool get isWindowsPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Whether a mouse is connected: arrows to page a row are for it, whatever the
/// platform. A desktop has one in practice, a tablet only when it is plugged
/// in. Listen to [mouseConnection] to follow it.
bool get hasMouse => RendererBinding.instance.mouseTracker.mouseIsConnected;

/// Notifies when a mouse is connected or goes away.
Listenable get mouseConnection => RendererBinding.instance.mouseTracker;
