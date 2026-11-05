import 'package:flutter_test/flutter_test.dart';

import 'package:clowtec_inspector/core/app_updater.dart';

void main() {
  const body = '''
{
  "build": 5,
  "version": "1.0.0",
  "notes": "Map fixes",
  "apks": {
    "arm64-v8a": {"url": "https://example.test/a.apk", "sha256": "abc", "megabytes": 48}
  }
}''';

  test('a newer build for this ABI is an update', () {
    final update =
        AppUpdate.parse(body, currentBuild: 4, abi: 'arm64-v8a')!;
    expect(update.build, 5);
    expect(update.url, 'https://example.test/a.apk');
    expect(update.sha256, 'abc');
    expect(update.megabytes, 48);
  });

  test('the same or an older build is not', () {
    expect(AppUpdate.parse(body, currentBuild: 5, abi: 'arm64-v8a'), isNull);
    expect(AppUpdate.parse(body, currentBuild: 6, abi: 'arm64-v8a'), isNull);
  });

  test('a device whose ABI was not published is not offered the wrong APK', () {
    expect(AppUpdate.parse(body, currentBuild: 1, abi: 'armeabi-v7a'), isNull);
  });
}
