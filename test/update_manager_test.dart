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
  });

  test('picks the first fitting asset, else the release page', () {
    final release = {
      'html_url': 'https://github.com/o/r/releases/tag/v0.1.0',
      'assets': [
        {'name': 'Musify.apk', 'browser_download_url': 'https://x/universal'},
        {
          'name': 'Musify-arm64-v8a.apk',
          'browser_download_url': 'https://x/arm64',
        },
      ],
    };

    expect(
      pickUpdateAsset(release, ['Musify-arm64-v8a.apk', 'Musify.apk']),
      'https://x/arm64',
    );
    expect(pickUpdateAsset(release, ['Musify.apk']), 'https://x/universal');
    expect(
      pickUpdateAsset(release, ['Musify-linux-x64.deb']),
      release['html_url'],
    );
  });
}
