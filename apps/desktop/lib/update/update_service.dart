/// PC 端检查更新。
///
/// 与手机端同构但通道独立：只消费 `desktop-v*` 标签的 Release，选中其中的
/// Windows 安装包（.exe），镜像优先、直连兜底；下载后校验 SHA-256（优先
/// GitHub asset digest，缺失时回退同 Release 的 SHA256SUMS 资源）。
/// 请求只包含仓库与版本元数据，不含任何账本金额或本机标识。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

final class PcRelease {
  const PcRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.installerName,
    required this.installerUrl,
    required this.installerSize,
    required this.installerSha256,
    this.publishedAt,
  });

  final String version;
  final String tag;
  final String title;
  final String notes;
  final Uri pageUrl;
  final String installerName;
  final Uri installerUrl;
  final int installerSize;

  /// Lower-case hex SHA-256 without the `sha256:` prefix.
  final String installerSha256;
  final DateTime? publishedAt;

  String get sizeLabel {
    const mb = 1024 * 1024;
    return installerSize >= mb
        ? '${(installerSize / mb).toStringAsFixed(1)} MB'
        : '${(installerSize / 1024).toStringAsFixed(0)} KB';
  }
}

final class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latest,
    required this.hasUpdate,
  });

  final String currentVersion;
  final PcRelease? latest;
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

/// Compares dotted numeric versions; prefixes and pre-release suffixes ignored.
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

final class PcUpdateService {
  PcUpdateService({
    required this.client,
    Uri? releasesUri,
    this.mirrorPrefixes = defaultMirrorPrefixes,
  }) : releasesUri = releasesUri ??
            Uri.https(
              'api.github.com',
              '/repos/wacilimonster-source/fjob/releases',
              const {'per_page': '20'},
            );

  final http.Client client;
  final Uri releasesUri;

  /// Domestic relays tried before the direct GitHub endpoints, in order.
  /// Community services come and go — re-verify when a release stops
  /// updating. Only the URL prefix is rewritten; responses must still parse
  /// as the GitHub Releases JSON.
  static const List<String> defaultMirrorPrefixes = <String>[
    'https://gh-proxy.com/',
    'https://ghfast.top/',
  ];

  final List<String> mirrorPrefixes;

  static const String _userAgent = 'FJOB-Windows-UpdateChecker';

  Iterable<Uri> get _metadataCandidates sync* {
    final feed = releasesUri.toString();
    for (final prefix in mirrorPrefixes) {
      yield Uri.parse('$prefix$feed');
    }
    yield releasesUri;
  }

  List<Uri> downloadCandidates(Uri installerUrl) {
    final candidates = <Uri>[];
    if (installerUrl.host == 'github.com') {
      final url = installerUrl.toString();
      for (final prefix in mirrorPrefixes) {
        candidates.add(Uri.parse('$prefix$url'));
      }
    }
    candidates.add(installerUrl);
    return candidates;
  }

  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    UpdateException? failure;
    var directFeedEmpty = false;
    for (final candidate in _metadataCandidates) {
      final direct = candidate == releasesUri;
      try {
        final releases = await _fetchReleases(
          candidate,
          timeout: direct
              ? const Duration(seconds: 12)
              : const Duration(seconds: 6),
        );
        if (releases.isEmpty) {
          if (direct) directFeedEmpty = true;
          continue;
        }
        releases.sort((a, b) => compareVersions(b.version, a.version));
        final latest = releases.first;
        return UpdateCheckResult(
          currentVersion: currentVersion,
          latest: latest,
          hasUpdate: compareVersions(latest.version, currentVersion) > 0,
        );
      } on UpdateException catch (error) {
        failure = error;
      }
    }
    if (directFeedEmpty) {
      throw const UpdateException('暂时没有可用的 PC 发布版本。');
    }
    throw failure ?? const UpdateException('检查更新失败，请确认网络可用。');
  }

  Future<List<PcRelease>> _fetchReleases(
    Uri uri, {
    required Duration timeout,
  }) async {
    late final http.Response response;
    try {
      response = await client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': _userAgent,
        },
      ).timeout(timeout);
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
    final releases = <PcRelease>[];
    for (final item in decoded) {
      var release = _parseRelease(item);
      if (release == null && _hasPendingChecksums(item)) {
        // No asset digest: fetch the release's own SHA256SUMS and retry.
        final body = await _fetchChecksumsBody(item);
        if (body != null) release = _parseRelease(item, checksumsBody: body);
      }
      if (release != null) releases.add(release);
    }
    return releases;
  }

  /// True when the item is a `desktop-v*` release with an .exe asset and a
  /// SHA256SUMS asset but no usable asset digest.
  bool _hasPendingChecksums(Object? raw) {
    if (raw is! Map) return false;
    final tag = raw['tag_name'];
    if (tag is! String || !RegExp(r'^desktop-v\d').hasMatch(tag)) return false;
    final assets = raw['assets'];
    if (assets is! List) return false;
    var hasExe = false;
    var hasChecksums = false;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String) continue;
      if (name.toLowerCase().endsWith('.exe')) {
        hasExe = true;
        final digest = asset['digest'];
        if (digest is String &&
            RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest.toLowerCase())) {
          return false;
        }
      }
      final lower = name.toLowerCase();
      if (lower == 'sha256sums' || lower == 'sha256sums.txt') hasChecksums = true;
    }
    return hasExe && hasChecksums;
  }

  Future<String?> _fetchChecksumsBody(Object? raw) async {
    if (raw is! Map) return null;
    final assets = raw['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String ||
          url is! String ||
          !(name.toLowerCase() == 'sha256sums' ||
              name.toLowerCase() == 'sha256sums.txt')) {
        continue;
      }
      try {
        final response = await client.get(Uri.parse(url)).timeout(
              const Duration(seconds: 10),
            );
        if (response.statusCode == 200) {
          return utf8.decode(response.bodyBytes);
        }
      } on Object {
        // Without the checksums body the release is rejected, not trusted.
      }
    }
    return null;
  }

  /// PC 通道：仅 `desktop-v*` 标签，且必须带 Windows 安装包与可校验的
  /// SHA-256（asset digest 优先，缺失时用 [checksumsBody] 回退）。
  PcRelease? _parseRelease(Object? raw, {String? checksumsBody}) {
    if (raw is! Map) return null;
    if (raw['draft'] == true) return null;
    final tag = raw['tag_name'];
    if (tag is! String) return null;
    final match = RegExp(r'^desktop-v(\d+(?:\.\d+){0,3})').firstMatch(tag);
    if (match == null) return null;
    final version = match.group(1)!;

    final assets = raw['assets'];
    if (assets is! List) return null;
    Map<Object?, Object?>? installer;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is! String || !name.toLowerCase().endsWith('.exe')) continue;
      final currentName = installer?['name'];
      final prefersSetup = name.toLowerCase().contains('setup');
      final currentIsSetup =
          currentName is String && currentName.toLowerCase().contains('setup');
      if (installer == null || (prefersSetup && !currentIsSetup)) {
        installer = asset;
      }
    }
    if (installer == null) return null;
    final downloadUrl = installer['browser_download_url'];
    final name = installer['name'];
    if (downloadUrl is! String || name is! String) return null;

    final digest = _resolveDigest(installer, checksumsBody, name);
    if (digest == null) return null;

    final pageUrl = raw['html_url'];
    return PcRelease(
      version: version,
      tag: tag,
      title: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? raw['name'] as String
          : tag,
      notes: (raw['body'] as String?) ?? '',
      pageUrl: pageUrl is String && pageUrl.isNotEmpty
          ? Uri.parse(pageUrl)
          : Uri.parse('https://github.com/wacilimonster-source/fjob/releases'),
      installerName: name,
      installerUrl: Uri.parse(downloadUrl),
      installerSize: (installer['size'] as num?)?.toInt() ?? 0,
      installerSha256: digest,
      publishedAt: DateTime.tryParse((raw['published_at'] as String?) ?? ''),
    );
  }

  String? _resolveDigest(
    Map<Object?, Object?> installer,
    String? checksumsBody,
    String name,
  ) {
    final raw = installer['digest'];
    if (raw is String && raw.toLowerCase().startsWith('sha256:')) {
      final hex = raw.substring('sha256:'.length).toLowerCase();
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex;
    }
    if (checksumsBody == null) return null;
    for (final line in const LineSplitter().convert(checksumsBody)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final hex = parts[0].toLowerCase();
      final fileName = parts.sublist(1).join(' ').replaceAll('*', '');
      if (fileName == name && RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
        return hex;
      }
    }
    return null;
  }

  /// Downloads the installer through relay candidates, verifies SHA-256 and
  /// returns the verified file inside the system temp directory.
  Future<File> downloadInstaller(
    PcRelease release, {
    void Function(int received, int total)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}fjob-update');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final target = File(
        '${directory.path}${Platform.pathSeparator}${release.installerName}');
    Object? lastError;
    for (final candidate in downloadCandidates(release.installerUrl)) {
      if (cancelToken?.isCancelled ?? false) {
        throw const UpdateException('下载已取消。');
      }
      try {
        final request = http.Request('GET', candidate)
          ..headers['User-Agent'] = _userAgent;
        final response = await client.send(request).timeout(
              const Duration(seconds: 60),
            );
        if (response.statusCode != 200) {
          lastError = UpdateException('下载失败：HTTP ${response.statusCode}。');
          continue;
        }
        final total = response.contentLength ?? release.installerSize;
        var received = 0;
        final sink = target.openWrite();
        try {
          await for (final chunk in response.stream) {
            if (cancelToken?.isCancelled ?? false) {
              throw const UpdateException('下载已取消。');
            }
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        final verified = await verifyFileSha256(target, release.installerSha256);
        if (!verified) {
          await target.delete().catchError((_) => target);
          lastError = const UpdateException('安装包校验失败，已丢弃。');
          continue;
        }
        return target;
      } on UpdateException catch (error) {
        lastError = error;
      } on Object {
        lastError = const UpdateException('下载失败，请确认网络可用。');
      }
    }
    throw lastError is UpdateException
        ? lastError
        : const UpdateException('下载失败，请确认网络可用。');
  }

  /// True when [file] matches the expected lower-case hex SHA-256.
  static Future<bool> verifyFileSha256(File file, String expected) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString() == expected;
  }
}
