import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';

/// A blurred picture of the content behind the floating surfaces, taken while
/// that content rests. A phone cannot afford to blur what is behind a surface
/// on every frame, so its blurred surfaces show the slice of this picture
/// under them and are translucent (no blur) while there is none.
///
/// [BlurSnapshotScope] owns one and [BlurSnapshotSource] marks the content it
/// takes the picture of. Anything inside that content must not show it: the
/// picture would hold the surface itself.
class BlurSnapshot extends ChangeNotifier with WidgetsBindingObserver {
  BlurSnapshot() {
    floatingEffect.addListener(_onEffectChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  /// The picture is a fraction of the content's size: blurred, it loses
  /// nothing, and it costs a fraction to draw.
  static const pixelRatio = 0.5;
  // As blurred as the live blur (sigma 12), in the picture's own pixels.
  static const _sigma = 12 * pixelRatio;

  // After a scroll, a theme or a setting changed the content.
  static const _settle = Duration(milliseconds: 150);
  // After the content painted: wait for it to stop painting.
  static const _idle = Duration(milliseconds: 300);
  // Without a scroll notification for this long, the content rests.
  static const _still = Duration(milliseconds: 400);
  // Between two pictures, and so the most often one is taken.
  static const _spacing = Duration(milliseconds: 400);
  // A second look after a picture, for what settles late (images, glows, a
  // page that was still sliding in).
  static const _recheck = Duration(milliseconds: 1000);

  /// The content the picture is taken of.
  final key = GlobalKey();

  /// Under the content, so the picture is opaque and hides what is under it.
  Color background = Colors.transparent;

  ui.Image? _image;
  ui.Image? get image => _image;

  // Counts what changed the content; the picture is current while it holds
  // the count it was taken at.
  int _version = 0;
  int _imageVersion = -1;
  bool _scrolling = false;
  bool _capturing = false;
  bool _recheckPending = false;
  bool _wasReady = false;
  bool _disposed = false;
  Timer? _timer;
  Timer? _spacingTimer;

  bool get _active =>
      isMobilePlatform && floatingEffect.value == FloatingEffect.blurred;

  /// Whether the picture shows what is behind the surfaces right now: the
  /// content is at rest and has not changed since it was taken.
  bool get ready => _image != null && !_scrolling && _imageVersion == _version;

  /// The picture a surface at [context] can show, or null when there is none
  /// or the surface is inside the content it is taken of.
  static BlurSnapshot? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SnapshotScope>();
    return scope == null || scope.captured ? null : scope.notifier;
  }

  /// The content may look different now (a theme, a setting, a scroll that
  /// ended): take a new picture soon, and look again later.
  void refresh() {
    if (!_active) return;
    _version++;
    _recheckPending = true;
    _publish();
    if (!_scrolling) _schedule(_settle);
  }

  /// The content painted or changed its size.
  void contentChanged() {
    if (!_active) return;
    _version++;
    _recheckPending = true;
    _publish();
    if (!_scrolling) _schedule(_idle);
  }

  bool onNotification(Notification notification) {
    switch (notification) {
      case ScrollMetricsNotification():
        contentChanged();
      case ScrollEndNotification():
        _scrolling = false;
        refresh();
      case ScrollStartNotification() ||
          ScrollUpdateNotification() ||
          OverscrollNotification():
        if (!_active) break;
        _scrolling = true;
        _publish();
        // A scroll that is cut off (its list is gone) never reports its end:
        // content that has not moved for a while rests.
        _timer?.cancel();
        _timer = Timer(_still, () {
          _scrolling = false;
          refresh();
        });
    }
    return false;
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _capture);
  }

  // Tells the surfaces, once the frame is over, when [ready] changed.
  void _publish() {
    if (ready == _wasReady) return;
    _wasReady = ready;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _capture() async {
    final boundary = key.currentContext?.findRenderObject();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_active ||
        _scrolling ||
        _capturing ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    // A debug build refuses a boundary that waits to be painted; that paint
    // reports itself, and the picture is taken after it.
    var painting = false;
    assert(() {
      painting = boundary.debugNeedsPaint;
      return true;
    }());
    if (painting) return;

    _capturing = true;
    final version = _version;
    final task = TimelineTask()..start('Zenify blur snapshot');
    ui.Image? blurred;
    try {
      final small = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        blurred = await _blur(small);
      } finally {
        small.dispose();
      }
    } catch (_) {
      // Whatever went wrong, the surfaces keep the translucent look.
    }
    task.finish();

    if (_disposed || !_active) {
      blurred?.dispose();
    } else if (blurred != null) {
      _image?.dispose();
      _image = blurred;
      _imageVersion = version;
      _wasReady = ready;
      notifyListeners();
      if (_recheckPending && version == _version) {
        _recheckPending = false;
        _schedule(_recheck);
      }
    }
    if (_disposed) return;
    // Stays "capturing" until the spacing is over; what changed meanwhile
    // gets its picture then.
    _spacingTimer = Timer(_spacing, () {
      _capturing = false;
      if (_version != version && !_scrolling) _schedule(_idle);
    });
  }

  Future<ui.Image> _blur(ui.Image source) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Paint()..color = background,
      )
      ..drawImage(
        source,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: _sigma,
            sigmaY: _sigma,
            tileMode: TileMode.clamp,
          ),
      );
    final picture = recorder.endRecording();
    return picture
        .toImage(source.width, source.height)
        .whenComplete(picture.dispose);
  }

  void _onEffectChanged() {
    if (_active) {
      refresh();
      return;
    }
    _timer?.cancel();
    _image?.dispose();
    _image = null;
    _publish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _spacingTimer?.cancel();
    floatingEffect.removeListener(_onEffectChanged);
    WidgetsBinding.instance.removeObserver(this);
    _image?.dispose();
    super.dispose();
  }
}

class _SnapshotScope extends InheritedNotifier<BlurSnapshot> {
  const _SnapshotScope({
    required BlurSnapshot snapshot,
    required this.captured,
    required super.child,
  }) : super(notifier: snapshot);

  /// Whether this part of the tree is inside the content that is captured.
  final bool captured;
}

/// Owns the [BlurSnapshot] of its subtree and offers it to the floating
/// surfaces in it. Wrap what it is taken of in a [BlurSnapshotSource].
class BlurSnapshotScope extends StatefulWidget {
  const BlurSnapshotScope({super.key, required this.child});

  final Widget child;

  @override
  State<BlurSnapshotScope> createState() => _BlurSnapshotScopeState();
}

class _BlurSnapshotScopeState extends State<BlurSnapshotScope> {
  final _snapshot = BlurSnapshot();

  // The first time, and whenever the theme changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _snapshot
      ..background = Theme.of(context).scaffoldBackgroundColor
      ..refresh();
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SnapshotScope(snapshot: _snapshot, captured: false, child: widget.child);
}

/// The content a [BlurSnapshotScope] takes its picture of: what the floating
/// surfaces sit over, and not the surfaces. Only phones take one.
class BlurSnapshotSource extends StatelessWidget {
  const BlurSnapshotSource({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_SnapshotScope>();
    if (scope == null || !isMobilePlatform) return child;
    final snapshot = scope.notifier!;
    return _SnapshotScope(
      snapshot: snapshot,
      captured: true,
      child: NotificationListener<Notification>(
        onNotification: snapshot.onNotification,
        child: RepaintBoundary(
          key: snapshot.key,
          child: _PaintProbe(onPaint: snapshot.contentChanged, child: child),
        ),
      ),
    );
  }
}

/// Reports each time the content is painted, which is how the picture knows
/// it no longer matches. A repaint boundary inside the content (a scroll view,
/// a list item) paints without this one, so scrolls and size changes report
/// themselves too.
class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) => renderObject.onPaint = onPaint;
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
