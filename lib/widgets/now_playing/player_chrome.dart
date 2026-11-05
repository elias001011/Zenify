import 'package:flutter/widgets.dart';

enum PlayerChromeStyle { plain, dock }

/// Shares presentation choices without duplicating playback controls.
class PlayerChrome extends InheritedWidget {
  const PlayerChrome({super.key, required this.style, required super.child});
  final PlayerChromeStyle style;

  static PlayerChromeStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerChrome>()!.style;

  @override
  bool updateShouldNotify(PlayerChrome oldWidget) => style != oldWidget.style;
}
