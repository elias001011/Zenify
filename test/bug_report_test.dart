import 'package:flutter_test/flutter_test.dart';
import 'package:musify/utilities/bug_report.dart';

void main() {
  test('opens the issue chooser, for a bug report or a feature suggestion', () {
    final uri = feedbackUri();

    expect(uri.host, 'github.com');
    expect(uri.path, '/elias001011/Zenify/issues/new/choose');
    expect(uri.hasQuery, isFalse);
  });
}
