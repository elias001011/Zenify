import 'package:flutter_test/flutter_test.dart';
import 'package:musify/constants/version.dart';
import 'package:musify/utilities/bug_report.dart';

void main() {
  test('opens a new bug report with the template and the version', () {
    final uri = bugReportUri(version: '0.2.1');

    expect(uri.host, 'github.com');
    expect(uri.path, '/elias001011/Zenify/issues/new');
    expect(uri.queryParameters['template'], 'bug_report.yml');
    expect(uri.queryParameters['title'], '[Bug] ');
    expect(uri.queryParameters['zenify-version'], '0.2.1');
  });

  test('the default version is the app version', () {
    expect(bugReportUri().queryParameters['zenify-version'], appVersion);
  });
}
