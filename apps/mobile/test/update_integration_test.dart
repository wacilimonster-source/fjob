// Real-network check against the public GitHub Releases feed.
//
// Run explicitly:
//   flutter test test/update_integration_test.dart --dart-define=FJOB_NETWORK_TESTS=true
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todayagain/data/update_service.dart';

void main() {
  test(
    'the public release feed exposes a signed APK with a digest',
    () async {
      final directory = Directory.systemTemp.createTempSync('fjob_net');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final service = UpdateService(
        client: http.Client(),
        temporaryDirectory: () async => directory,
      );
      final result = await service.checkForUpdate('0.1.1');
      expect(result.hasUpdate, isTrue);
      expect(result.latest, isNotNull);
      expect(compareVersions(result.latest!.version, '0.1.1'), greaterThan(0));
      expect(result.latest!.apkUrl.path, endsWith('.apk'));
      expect(result.latest!.apkSha256, hasLength(64));
      expect(result.latest!.apkSize, greaterThan(0));
      expect(result.latest!.pageUrl.toString(), contains('/releases/tag/'));
      // ignore: avoid_print
      print(
        'latest=${result.latest!.version} asset=${result.latest!.apkName} '
        'size=${result.latest!.sizeLabel} sha256=${result.latest!.apkSha256}',
      );
    },
    skip: !const bool.fromEnvironment('FJOB_NETWORK_TESTS'),
  );
}
