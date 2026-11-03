import 'package:flutter/widgets.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Suspends UI tickers while the app is hidden, preserving playback.
class AppMotion extends StatefulWidget {
  const AppMotion({super.key, required this.child});
  final Widget child;

  @override
  State<AppMotion> createState() => _AppMotionState();
}

class _AppMotionState extends State<AppMotion> {
  late final AppLifecycleListener _lifecycle;
  bool _visible = true;

  bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      (isDesktopPlatform && state == AppLifecycleState.inactive);

  @override
  void initState() {
    super.initState();
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final visible = _isVisible(state);
        if (visible != _visible) setState(() => _visible = visible);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: _visible && TickerMode.valuesOf(context).enabled,
    child: widget.child,
  );
}
