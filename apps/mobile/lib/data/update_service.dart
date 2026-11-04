/// In-app update check and APK download.
///
/// The checker talks to the public GitHub Releases API for
/// `wacilimonster-source/fjob`, compares semantic versions with the installed
/// build, downloads the universal APK over HTTPS, verifies the server-provided
/// SHA-256 digest and hands the file to the Android installer. No ledger value
/// or account data leaves the device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

final class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.apkUrl,
    required this.apkSize,
    required this.apkSha256,
    this.publishedAt,
  });

  final String version;
  final String tag;
  final String title;
  final String notes;
  final Uri pageUrl;
  final Uri apkUrl;
  final int apkSize;

  /// Lower-case hex SHA-256 without the `sha256:` prefix.
  final String apkSha256;
  final DateTime? publishedAt;

  String get apkName => apkUrl.pathSegments.isEmpty
      ? 'fjob-$version.apk'
      : apkUrl.pathSegments.last;

  String get sizeLabel {
    const mb = 1024 * 1024;
    return apkSize >= mb
        ? '${(apkSize / mb).toStringAsFixed(1)} MB'
        : '${(apkSize / 1024).toStringAsFixed(0)} KB';
  }
}

final class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latest,
    required this.hasUpdate,
  });

  final String currentVersion;
  final AppRelease? latest;
  final bool hasUpdate;
}

final class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DownloadCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Compares dotted numeric versions; `v` prefix and pre-release suffix ignored.
int compareVersions(String a, String b) {
  List<int> numbers(String value) {
    final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(value);
    if (match == null) return const [0];
    return match.group(1)!.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  }

  final left = numbers(a);
  final right = numbers(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    final l = index < left.length ? left[index] : 0;
    final r = index < right.length ? right[index] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

final class UpdateService {
  UpdateService({
    required this.client,
    required this.temporaryDirectory,
    Uri? releasesUri,
  }) : releasesUri = releasesUri ??
            Uri.https(
              'api.github.com',
              '/repos/wacilimonster-source/fjob/releases',
              const {'per_page': '20'},
            );

  final http.Client client;
  final Future<Directory> Function() temporaryDirectory;
  final Uri releasesUri;

  static const String _userAgent = 'FJOB-Android-UpdateChecker';

  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    late final http.Response response;
    try {
      response = await client.get(
        releasesUri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': _userAgent,
        },
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const UpdateException('检查更新超时，稍后再试。');
    } on Object {
      throw const UpdateException('检查更新失败，请确认网络可用。');
    }
    if (response.statusCode != 200) {
      throw UpdateException('检查更新失败：HTTP ${response.statusCode}。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const UpdateException('更新信息格式无法解析。');
    }
    if (decoded is! List) {
      throw const UpdateException('更新信息格式无法解析。');
    }

    final releases = <AppRelease>[];
    for (final item in decoded) {
      final release = _parseRelease(item);
      if (release != null) releases.add(release);
    }
    if (releases.isEmpty) {
      throw const UpdateException('暂时没有可用的发布版本。');
    }
    releases.sort((a, b) => compareVersions(b.version, a.version));
    final latest = releases.first;
    return UpdateCheckResult(
      currentVersion: currentVersion,
      latest: latest,
      hasUpdate: compareVersions(latest.version, currentVersion) > 0,
    );
  }

  AppRelease? _parseRelease(Object? raw) {
    if (raw is! Map) return null;
    if (raw['draft'] == true) return null;
    final tag = raw['tag_name'];
    if (tag is! String) return null;
    final match = RegExp(r'^v?(\d+(?:\.\d+){0,3})').firstMatch(tag);
    if (match == null) return null;
    final version = match.group(1)!;

    final assets = raw['assets'];
    if (assets is! List) return null;
    Map<Object?, Object?>? apk;
    Map<Object?, Object?>? universal;
    final abiToken = _preferredAbiToken();
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String || !name.endsWith('.apk')) continue;
      if (universal == null && name.contains('universal')) universal = asset;
      if (abiToken != null && apk == null && name.contains(abiToken)) {
        apk = asset;
      }
    }
    apk ??= universal;
    if (apk == null) {
      for (final asset in assets) {
        if (asset is Map && asset['name'] is String &&
            (asset['name']! as String).endsWith('.apk')) {
          apk = asset;
          break;
        }
      }
    }
    if (apk == null) return null;
    final downloadUrl = apk['browser_download_url'];
    if (downloadUrl is! String) return null;
    final digestRaw = apk['digest'];
    if (digestRaw is! String || !digestRaw.startsWith('sha256:')) return null;
    final digest = digestRaw.substring('sha256:'.length).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return null;

    final pageUrl = raw['html_url'];
    return AppRelease(
      version: version,
      tag: tag,
      title: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? raw['name'] as String
          : tag,
      notes: (raw['body'] as String?) ?? '',
      pageUrl: pageUrl is String && pageUrl.isNotEmpty
          ? Uri.parse(pageUrl)
          : Uri.parse('https://github.com/wacilimonster-source/fjob/releases'),
      apkUrl: Uri.parse(downloadUrl),
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      apkSha256: digest,
      publishedAt: DateTime.tryParse((raw['published_at'] as String?) ?? ''),
    );
  }

  /// Split-ABI releases are smaller than the universal APK; prefer the
  /// matching ABI when the release publishes one.
  String? _preferredAbiToken() {
    if (!Platform.isAndroid) return null;
    return switch (Abi.current()) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidX64 => 'x86_64',
      _ => null,
    };
  }

  Future<File> downloadApk(
    AppRelease release, {
    required void Function(double progress) onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final directory = Directory('${(await temporaryDirectory()).path}/updates');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${release.apkName}');
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', release.apkUrl)
      ..headers['User-Agent'] = _userAgent;
    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(const Duration(seconds: 20));
    } on Object {
      throw const UpdateException('下载失败，请检查网络后重试。');
    }
    if (response.statusCode != 200) {
      throw UpdateException('下载失败：HTTP ${response.statusCode}。');
    }
    final total = response.contentLength ?? release.apkSize;
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (cancelToken?.isCancelled == true) {
          throw const UpdateException('下载已取消。');
        }
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      hasher.close();
    } on Object {
      await sink.flush().catchError((Object _) {});
      await sink.close().catchError((Object _) {});
      if (await file.exists()) await file.delete();
      rethrow;
    }

    final digest = digestSink.value?.toString() ?? '';
    if (digest != release.apkSha256) {
      if (await file.exists()) await file.delete();
      throw const UpdateException('安装包校验失败，已删除下载文件。');
    }
    if (release.apkSize > 0 && received != release.apkSize) {
      if (await file.exists()) await file.delete();
      throw const UpdateException('安装包大小不一致，请重试。');
    }
    onProgress(1);
    return file;
  }
}

abstract interface class ApkInstallBridge {
  Future<bool> canRequestInstall();

  Future<void> openInstallPermissionSettings();

  Future<bool> installApk(String path);
}

final class MethodChannelApkInstallBridge implements ApkInstallBridge {
  const MethodChannelApkInstallBridge({
    this.channel = const MethodChannel('cn.fjob.todayagain/updates'),
  });

  final MethodChannel channel;

  @override
  Future<bool> canRequestInstall() async {
    try {
      return await channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    try {
      await channel.invokeMethod<void>('openInstallPermissionSettings');
    } on PlatformException {
      // The system settings screen may be unavailable on some OEMs.
    } on MissingPluginException {
      // Desktop/test hosts have no installer.
    }
  }

  @override
  Future<bool> installApk(String path) async {
    try {
      return await channel.invokeMethod<bool>('installApk', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
