import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todayagain_desktop/update/update_service.dart';

const String _hexA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hexB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _hexC = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _hexZero = '0000000000000000000000000000000000000000000000000000000000000000';

Map<String, Object?> _release({
  required String tag,
  required List<Map<String, Object?>> assets,
  String? name,
  String? body,
}) {
  return {
    'tag_name': tag,
    'name': name ?? tag,
    'body': body ?? '',
    'draft': false,
    'html_url': 'https://github.com/wacilimonster-source/fjob/releases/tag/$tag',
    'published_at': '2026-11-11T10:00:00Z',
    'assets': assets,
  };
}

Map<String, Object?> _exeAsset({
  required String name,
  String digest = 'sha256:$_hexA',
  int size = 13 * 1024 * 1024,
}) {
  return {
    'name': name,
    'browser_download_url':
        'https://github.com/wacilimonster-source/fjob/releases/download/x/$name',
    'size': size,
    'digest': digest,
  };
}

String _feed(List<Map<String, Object?>> releases) =>
    jsonEncode(releases);


http.Response _jsonResponse(List<Map<String, Object?>> releases) =>
    http.Response.bytes(utf8.encode(_feed(releases)), 200);

void main() {
  group('compareVersions', () {
    test('orders dotted numeric versions', () {
      expect(compareVersions('0.1.0', '0.1.0'), 0);
      expect(compareVersions('0.2.0', '0.1.0'), greaterThan(0));
      expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('0.1', '0.1.0'), 0);
    });
  });

  group('checkForUpdate channel isolation', () {
    test('picks the newest desktop-v release with a verified installer',
        () async {
      final client = MockClient((request) async {
        return _jsonResponse([
            _release(tag: 'v0.1.10', assets: [
              {'name': 'fjob-0.1.10-universal.apk', 'browser_download_url': 'https://x/a.apk'},
            ]),
            _release(
              tag: 'desktop-v0.1.0',
              assets: [_exeAsset(name: 'FJOB-Setup-0.1.0.exe')],
            ),
            _release(
              tag: 'desktop-v0.2.0',
              name: 'PC 0.2.0',
              body: '首个安装包版本',
              assets: [_exeAsset(name: 'FJOB-Setup-0.2.0.exe')],
            ),
        ]);
      });
      final service = PcUpdateService(client: client);
      final result = await service.checkForUpdate('0.1.0');
      expect(result.hasUpdate, isTrue);
      expect(result.latest?.version, '0.2.0');
      expect(result.latest?.tag, 'desktop-v0.2.0');
      expect(result.latest?.installerName, 'FJOB-Setup-0.2.0.exe');
      expect(result.latest?.notes, '首个安装包版本');
      expect(result.latest?.sizeLabel, isNotEmpty);
    });

    test('mobile-only releases are not picked (no misinstall)', () async {
      final client = MockClient((request) async {
        return _jsonResponse([
            _release(tag: 'v0.1.10', assets: [
              {'name': 'fjob-0.1.10-universal.apk'},
            ]),
        ]);
      });
      final service = PcUpdateService(client: client);
      await expectLater(
        service.checkForUpdate('0.1.0'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('desktop-v without an .exe asset is ignored', () async {
      final client = MockClient((request) async {
        return _jsonResponse([
            _release(tag: 'desktop-v0.2.0', assets: [
              {'name': 'fjob-desktop-0.2.0-win-x64.zip'},
            ]),
        ]);
      });
      final service = PcUpdateService(client: client);
      await expectLater(
        service.checkForUpdate('0.1.0'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('asset without digest or SHA256SUMS is rejected, not trusted',
        () async {
      final client = MockClient((request) async {
        return _jsonResponse([
            _release(tag: 'desktop-v0.2.0', assets: [
              _exeAsset(name: 'FJOB-Setup-0.2.0.exe', digest: ''),
            ]),
        ]);
      });
      final service = PcUpdateService(client: client);
      await expectLater(
        service.checkForUpdate('0.1.0'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('falls back to the release SHA256SUMS asset when digest is absent',
        () async {
      const hex = _hexB;
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('SHA256SUMS')) {
          return http.Response('$hex  FJOB-Setup-0.2.0.exe\n', 200);
        }
        return _jsonResponse([
            _release(tag: 'desktop-v0.2.0', assets: [
              _exeAsset(name: 'FJOB-Setup-0.2.0.exe', digest: ''),
              {
                'name': 'SHA256SUMS',
                'browser_download_url':
                    'https://github.com/wacilimonster-source/fjob/releases/download/x/SHA256SUMS',
              },
            ]),
        ]);
      });
      final service = PcUpdateService(client: client);
      final result = await service.checkForUpdate('0.1.0');
      expect(result.hasUpdate, isTrue);
      expect(result.latest?.installerSha256, hex);
    });

    test('up to date when the newest release equals the build', () async {
      final client = MockClient((request) async {
        return _jsonResponse([
            _release(
              tag: 'desktop-v0.1.0',
              assets: [_exeAsset(name: 'FJOB-Setup-0.1.0.exe')],
            ),
        ]);
      });
      final service = PcUpdateService(client: client);
      final result = await service.checkForUpdate('0.1.0');
      expect(result.hasUpdate, isFalse);
      expect(result.latest?.version, '0.1.0');
    });

    test('relay failure falls back to the direct endpoint', () async {
      final client = MockClient((request) async {
        final host = request.url.host;
        if (host == 'gh-proxy.com') {
          return http.Response('blocked', 502);
        }
        return _jsonResponse([
            _release(
              tag: 'desktop-v0.2.0',
              assets: [_exeAsset(name: 'FJOB-Setup-0.2.0.exe')],
            ),
        ]);
      });
      final service = PcUpdateService(client: client);
      final result = await service.checkForUpdate('0.1.0');
      expect(result.hasUpdate, isTrue);
    });
  });

  group('downloadInstaller', () {
    test('downloads and verifies the installer SHA-256', () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      final hex = _sha256Hex(bytes);
      final client = MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      });
      final service = PcUpdateService(client: client);
      final release = PcRelease(
        version: '0.2.0',
        tag: 'desktop-v0.2.0',
        title: 'desktop-v0.2.0',
        notes: '',
        pageUrl: Uri.parse('https://github.com/x/y'),
        installerName: 'FJOB-Setup-0.2.0.exe',
        installerUrl: Uri.parse(
            'https://github.com/wacilimonster-source/fjob/releases/download/x/FJOB-Setup-0.2.0.exe'),
        installerSize: bytes.length,
        installerSha256: hex,
      );
      final file = await service.downloadInstaller(release);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), bytes.length);
      expect(file.path.contains('fjob-update'), isTrue);
    });

    test('tampered download is discarded', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(utf8.encode('not the installer'), 200);
      });
      final service = PcUpdateService(client: client);
      final release = PcRelease(
        version: '0.2.0',
        tag: 'desktop-v0.2.0',
        title: 'desktop-v0.2.0',
        notes: '',
        pageUrl: Uri.parse('https://github.com/x/y'),
        installerName: 'FJOB-Setup-0.2.0.exe',
        installerUrl: Uri.parse(
            'https://github.com/wacilimonster-source/fjob/releases/download/x/FJOB-Setup-0.2.0.exe'),
        installerSize: 17,
        installerSha256: _hexC,
      );
      await expectLater(
        service.downloadInstaller(release),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('verifyFileSha256', () {
    test('matches and rejects', () async {
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}fjob-sha-test.bin');
      await file.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      expect(await PcUpdateService.verifyFileSha256(file, _sha256Hex([1, 2, 3, 4])),
          isTrue);
      expect(await PcUpdateService.verifyFileSha256(file, _hexZero), isFalse);
      expect(await PcUpdateService.verifyFileSha256(file, 'nothex'), isFalse);
    });
  });
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
