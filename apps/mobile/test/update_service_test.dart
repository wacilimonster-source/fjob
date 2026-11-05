import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todayagain/data/update_service.dart';

String _digestOf(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, Object?> _release({
  required String tag,
  required String url,
  required int size,
  required String digest,
  bool draft = false,
  String? name,
}) =>
    {
      'tag_name': tag,
      'name': name ?? 'Release $tag',
      'draft': draft,
      'prerelease': true,
      'body': '## 变更\n- 固定浅色主题',
      'html_url': 'https://github.com/wacilimonster-source/fjob/releases/tag/$tag',
      'published_at': '2026-11-04T12:00:00Z',
      'assets': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'notes.txt',
          'size': 10,
          'digest': 'sha256:${'b' * 64}',
          'browser_download_url': 'https://example.com/notes.txt',
        },
        <String, Object?>{
          'name': 'fjob-${tag.replaceFirst('v', '')}-universal.apk',
          'size': size,
          'digest': 'sha256:$digest',
          'browser_download_url': url,
        },
      ],
    };

void main() {
  group('compareVersions', () {
    test('orders dotted versions numerically', () {
      expect(compareVersions('0.1.2', '0.1.3'), lessThan(0));
      expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
      expect(compareVersions('v0.1.2', '0.1.2'), 0);
      expect(compareVersions('0.2', '0.1.9'), greaterThan(0));
    });
  });

  group('checkForUpdate', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('fjob_update');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    UpdateService serviceWith(List<Object?> releases) => UpdateService(
          client: MockClient((request) async {
            expect(request.headers['User-Agent'], isNotEmpty);
            return http.Response(
              jsonEncode(releases),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
          temporaryDirectory: () async => directory,
        );

    test('picks the highest non-draft release with a universal APK', () async {
      final service = serviceWith([
        _release(
          tag: 'v0.1.1',
          url: 'https://example.com/fjob-0.1.1-universal.apk',
          size: 10,
          digest: 'a' * 64,
        ),
        _release(
          tag: 'v0.1.3',
          url: 'https://example.com/fjob-0.1.3-universal.apk',
          size: 20,
          digest: 'c' * 64,
          name: 'v0.1.3 更新',
        ),
        _release(
          tag: 'v9.0.0',
          url: 'https://example.com/fjob-9.0.0-universal.apk',
          size: 30,
          digest: 'd' * 64,
          draft: true,
        ),
      ]);
      final result = await service.checkForUpdate('0.1.2');
      expect(result.hasUpdate, isTrue);
      expect(result.latest!.version, '0.1.3');
      expect(result.latest!.apkName, 'fjob-0.1.3-universal.apk');
      expect(result.latest!.apkSha256, 'c' * 64);
      expect(result.latest!.title, 'v0.1.3 更新');
      expect(result.latest!.notes, contains('固定浅色'));
    });

    test('reports up to date when the installed version is current', () async {
      final service = serviceWith([
        _release(
          tag: 'v0.1.2',
          url: 'https://example.com/fjob-0.1.2-universal.apk',
          size: 10,
          digest: 'a' * 64,
        ),
      ]);
      final result = await service.checkForUpdate('0.1.2');
      expect(result.hasUpdate, isFalse);
      expect(result.latest!.version, '0.1.2');
    });

    test('ignores assets without a SHA-256 digest', () async {
      final release = _release(
        tag: 'v0.1.3',
        url: 'https://example.com/fjob-0.1.3-universal.apk',
        size: 10,
        digest: 'a' * 64,
      );
      final assets = release['assets']! as List<Object?>;
      (assets.last! as Map<String, Object?>)['digest'] = null;
      final service = serviceWith([release]);
      expect(
        () => service.checkForUpdate('0.1.2'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('surfaces HTTP failures', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('nope', 503)),
        temporaryDirectory: () async => directory,
      );
      expect(
        () => service.checkForUpdate('0.1.2'),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('asks the domestic relay first and rewrites the feed URL', () async {
      final requested = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            jsonEncode([
              _release(
                tag: 'v0.1.3',
                url: 'https://example.com/fjob-0.1.3-universal.apk',
                size: 10,
                digest: 'a' * 64,
              ),
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        temporaryDirectory: () async => directory,
      );
      final result = await service.checkForUpdate('0.1.2');
      expect(result.hasUpdate, isTrue);
      expect(requested, hasLength(1));
      expect(requested.single.host, 'gh-proxy.com');
      expect(
        requested.single.toString(),
        startsWith('https://gh-proxy.com/https://api.github.com/'),
      );
    });

    test('falls back to the direct feed when relays misbehave', () async {
      final requested = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == 'api.github.com') {
            return http.Response(
              jsonEncode([
                _release(
                  tag: 'v0.1.3',
                  url: 'https://example.com/fjob-0.1.3-universal.apk',
                  size: 10,
                  digest: 'a' * 64,
                ),
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Both relays answer with an unparseable page.
          return http.Response('<html>blocked</html>', 200);
        }),
        temporaryDirectory: () async => directory,
      );
      final result = await service.checkForUpdate('0.1.2');
      expect(result.hasUpdate, isTrue);
      expect(requested.map((uri) => uri.host).toList(),
          ['gh-proxy.com', 'ghfast.top', 'api.github.com']);
    });
  });

  group('downloadApk', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('fjob_download');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    final payload = List<int>.generate(2048, (index) => index % 251);

    AppRelease releaseFor(
      List<int> bytes, {
      String? digest,
      int? size,
      Uri? apkUrl,
    }) =>
        AppRelease(
          version: '0.1.3',
          tag: 'v0.1.3',
          title: 'v0.1.3',
          notes: '',
          pageUrl: Uri.parse('https://example.com/release'),
          apkUrl: apkUrl ??
              Uri.parse('https://example.com/fjob-0.1.3-universal.apk'),
          apkSize: size ?? bytes.length,
          apkSha256: digest ?? _digestOf(bytes),
        );

    UpdateService downloadService() => UpdateService(
          client: MockClient((request) async {
            return http.Response.bytes(
              payload,
              200,
              headers: {'content-length': '${payload.length}'},
            );
          }),
          temporaryDirectory: () async => directory,
        );

    test('downloads, verifies and reports progress', () async {
      final progress = <double>[];
      final file = await downloadService().downloadApk(
        releaseFor(payload),
        onProgress: progress.add,
      );
      expect(await file.readAsBytes(), payload);
      expect(progress.last, 1);
      expect(progress.length, greaterThan(1));
      expect(file.path, contains('updates'));
    });

    test('deletes the file when the digest does not match', () async {
      await expectLater(
        downloadService().downloadApk(
          releaseFor(payload, digest: 'f' * 64),
          onProgress: (_) {},
        ),
        throwsA(isA<UpdateException>()),
      );
      final files = Directory('${directory.path}/updates').listSync();
      expect(files, isEmpty);
    });

    test('deletes the file when the size does not match', () async {
      await expectLater(
        downloadService().downloadApk(
          releaseFor(payload, size: payload.length + 10),
          onProgress: (_) {},
        ),
        throwsA(isA<UpdateException>()),
      );
      final files = Directory('${directory.path}/updates').listSync();
      expect(files, isEmpty);
    });

    test('cancellation stops the download and removes the partial file',
        () async {
      final token = DownloadCancelToken();
      final service = UpdateService(
        client: MockClient((request) async {
          token.cancel();
          return http.Response.bytes(payload, 200);
        }),
        temporaryDirectory: () async => directory,
      );
      await expectLater(
        service.downloadApk(
          releaseFor(payload),
          onProgress: (_) {},
          cancelToken: token,
        ),
        throwsA(isA<UpdateException>()),
      );
    });

    test('downloads a GitHub asset through the domestic relay first',
        () async {
      final requested = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(
            payload,
            200,
            headers: {'content-length': '${payload.length}'},
          );
        }),
        temporaryDirectory: () async => directory,
      );
      final file = await service.downloadApk(
        releaseFor(
          payload,
          apkUrl: Uri.parse(
            'https://github.com/wacilimonster-source/fjob/releases/download/'
            'v0.1.3/fjob-0.1.3-universal.apk',
          ),
        ),
        onProgress: (_) {},
      );
      expect(await file.readAsBytes(), payload);
      expect(requested, hasLength(1));
      expect(requested.single.host, 'gh-proxy.com');
      expect(
        requested.single.toString(),
        startsWith('https://gh-proxy.com/https://github.com/'),
      );
    });

    test('falls back to the direct URL when the relays fail', () async {
      final requested = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == 'github.com') {
            return http.Response.bytes(
              payload,
              200,
              headers: {'content-length': '${payload.length}'},
            );
          }
          return http.Response('forbidden', 403);
        }),
        temporaryDirectory: () async => directory,
      );
      final file = await service.downloadApk(
        releaseFor(
          payload,
          apkUrl: Uri.parse(
            'https://github.com/wacilimonster-source/fjob/releases/download/'
            'v0.1.3/fjob-0.1.3-universal.apk',
          ),
        ),
        onProgress: (_) {},
      );
      expect(await file.readAsBytes(), payload);
      expect(requested.map((uri) => uri.host).toList(),
          ['gh-proxy.com', 'ghfast.top', 'github.com']);
    });

    test('never rewrites non-GitHub asset hosts', () async {
      final requested = <Uri>[];
      final service = UpdateService(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(
            payload,
            200,
            headers: {'content-length': '${payload.length}'},
          );
        }),
        temporaryDirectory: () async => directory,
      );
      await service.downloadApk(
        releaseFor(payload),
        onProgress: (_) {},
      );
      expect(requested.single.toString(),
          'https://example.com/fjob-0.1.3-universal.apk');
    });
  });

}
