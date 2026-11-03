import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/services/settings_manager.dart';

/// Shares one settings subscription across visible music rows.
class MusicSurfaceTheme extends StatelessWidget {
  const MusicSurfaceTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([floatingEffect, dynamicBackground]),
    child: child,
    builder: (context, child) => _MusicSurfaceStyle(
      effect: dynamicBackground.value
          ? floatingEffect.value
          : FloatingEffect.solid,
      child: child!,
    ),
  );
}

class _MusicSurfaceStyle extends InheritedWidget {
  const _MusicSurfaceStyle({required this.effect, required super.child});
  final FloatingEffect effect;

  @override
  bool updateShouldNotify(_MusicSurfaceStyle oldWidget) =>
      effect != oldWidget.effect;
}

class _MusicListGroup extends InheritedWidget {
  const _MusicListGroup({required super.child});
  @override
  bool updateShouldNotify(_MusicListGroup oldWidget) => false;
}

/// One continuous background prevents seams between fractional row boundaries.
class MusicSliverSurface extends StatelessWidget {
  const MusicSliverSurface({super.key, required this.sliver});
  final Widget sliver;

  @override
  Widget build(BuildContext context) => _MusicListGroup(
    child: DecoratedSliver(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: commonCustomBarRadius,
      ),
      sliver: sliver,
    ),
  );
}

Color _surfaceColor(BuildContext context, [Color? color]) {
  final theme = Theme.of(context);
  final effect =
      context
          .dependOnInheritedWidgetOfExactType<_MusicSurfaceStyle>()
          ?.effect ??
      (dynamicBackground.value ? floatingEffect.value : FloatingEffect.solid);
  final base = color ?? theme.colorScheme.surfaceContainerLow;
  return effect == FloatingEffect.solid
      ? base
      : base.withValues(
          alpha: base.a * (theme.brightness == Brightness.dark ? 0.5 : 0.72),
        );
}

class MusicListSurface extends StatelessWidget {
  const MusicListSurface({
    super.key,
    this.color,
    this.borderRadius,
    required this.child,
    this.emphasized = false,
  });

  final Color? color;
  final BorderRadius? borderRadius;
  final Widget child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final grouped =
        context.dependOnInheritedWidgetOfExactType<_MusicListGroup>() != null;
    return Material(
      color: emphasized
          ? color ?? Theme.of(context).colorScheme.surfaceContainerLow
          : grouped
          ? Colors.transparent
          : _surfaceColor(context, color),
      borderRadius: borderRadius ?? commonCustomBarRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
