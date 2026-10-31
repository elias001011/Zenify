import 'package:musify/constants/version.dart';

/// The page for a new bug report on Zenify's issues, with the version filled
/// in and the bug report template chosen.
Uri bugReportUri({String version = appVersion}) => Uri.https(
  'github.com',
  '/elias001011/Zenify/issues/new',
  {'template': 'bug_report.yml', 'title': '[Bug] ', 'zenify-version': version},
);
