import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/widgets/app_motion.dart';

class _AnimatedChild extends StatefulWidget {
  const _AnimatedChild({required this.onTick});
  final VoidCallback onTick;
  @override
  State<_AnimatedChild> createState() => _AnimatedChildState();
}

class _AnimatedChildState extends State<_AnimatedChild>
    with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  @override
  void initState() {
    super.initState();
    ticker = createTicker((_) => widget.onTick())..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('hidden apps stop UI frames and resume without remounting', (
    tester,
  ) async {
    final binding = tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    var ticks = 0;
    await tester.pumpWidget(
      AppMotion(child: _AnimatedChild(onTick: () => ticks++)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(0));
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hidden = ticks;
    await tester.pump(const Duration(seconds: 5));
    expect(ticks, hidden);
    expect(binding.hasScheduledFrame, isFalse);
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ticks, greaterThan(hidden));
    await tester.pumpWidget(const SizedBox());
  });
}
