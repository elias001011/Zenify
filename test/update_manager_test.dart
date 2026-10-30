import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/update_manager.dart';

void main() {
  test('compares versions number by number', () {
    expect(isLatestVersionHigher('0.1.0', '0.1.1'), isTrue);
    expect(isLatestVersionHigher('0.1.0', '0.2'), isTrue);
    expect(isLatestVersionHigher('0.10.0', '0.9.9'), isFalse);
    expect(isLatestVersionHigher('0.1.0', '0.1.0'), isFalse);
    expect(isLatestVersionHigher('0.1.0', '0.1.0-1'), isTrue);
    expect(isLatestVersionHigher('1.0.0', 'unknown'), isFalse);
    expect(isLatestVersionHigher('0.1.7', '0.1.7.1'), isTrue);
    expect(isLatestVersionHigher('0.1.7.1', '0.1.8'), isTrue);
    expect(isLatestVersionHigher('0.1.7.1', '0.1.7.10'), isTrue);
    expect(isLatestVersionHigher('0.1.7.10', '0.1.7.2'), isFalse);
  });

  test('picks the first fitting asset, else the release page', () {
    final release = {
      'html_url': 'https://github.com/o/r/releases/tag/v0.1.0',
      'assets': [
        {'name': 'Zenify.apk', 'browser_download_url': 'https://x/universal'},
        {
          'name': 'Zenify-arm64-v8a.apk',
          'browser_download_url': 'https://x/arm64',
        },
      ],
    };

    expect(
      pickUpdateAsset(release, ['Zenify-arm64-v8a.apk', 'Zenify.apk']),
      'https://x/arm64',
    );
    expect(pickUpdateAsset(release, ['Zenify.apk']), 'https://x/universal');
    expect(
      pickUpdateAsset(release, ['Zenify-linux-x64.deb']),
      release['html_url'],
    );
  });
}
