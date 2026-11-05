import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/logger_service.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('the log keeps the latest entries only', (tester) async {
    final printer = debugPrint;
    debugPrint = (message, {wrapWidth}) {};

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final logger = Logger();
    for (var i = 0; i < 700; i++) {
      logger.log('entry $i');
    }
    debugPrint = printer;
    // The counter still counts every entry, kept or not.
    expect(logger.getLogCount(), 700);

    late BuildContext context;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.runAsync(() => logger.copyLogs(context));

    final entries = RegExp(r'entry (\d+):')
        .allMatches(copied!)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(entries.length, 500);
    expect(entries.first, 200);
    expect(entries.last, 699);
  });
}
