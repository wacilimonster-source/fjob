import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'address.dart';
import 'crypto.dart';
import 'protocol.dart';

/// PC-side guest for one phone-hosted LAN session.
final class LanTransferClient {
  LanTransferClient({
    http.Client? client,
    this.probeTimeout = const Duration(seconds: 8),
    this.transferTimeout = const Duration(seconds: 60),
    this.maxBundleBytes = defaultMaxBundleBytes,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration probeTimeout;
  final Duration transferTimeout;
  final int maxBundleBytes;

  Future<LanSessionInfo> probe(LanAddress address) async {
    final uri = Uri.http(address.authority, '/session');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(probeTimeout);
    } on TimeoutException {
      throw const LanTransferException('连接手机超时，请确认地址和同一 Wi-Fi。');
    } on Object {
      throw const LanTransferException('连不上手机，请确认同一 Wi-Fi、地址和配对码正确。');
    }
    if (response.statusCode != 200) {
      throw _mapError(response.statusCode);
    }
    try {
      return LanSessionInfo.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } on FormatException {
      throw const LanTransferException('手机返回的会话信息无法解析。');
    }
  }

  /// Pulls the phone's ledger after the phone started a "send to PC" session.
  Future<LanPullPayload> pull({
    required LanAddress address,
    required String code,
  }) async {
    final info = await probe(address);
    if (info.mode != LanTransferMode.send) {
      throw const LanTransferException(
        '手机当前在「从电脑接收」模式；请让手机选择「发送到电脑」。',
      );
    }
    final key = await LanCrypto.deriveKey(code: code, salt: info.saltBytes);
    final payload = await _post(
      address,
      key,
      info,
      {
        'v': lanProtocolVersion,
        'challenge': info.challengeBase64,
        'client': 'windows',
        'action': 'pull',
      },
    );
    final fileName = payload['fileName'];
    final bundle = payload['bundle'];
    if (payload['ok'] != true || fileName is! String || bundle is! String) {
      throw const LanTransferException('手机返回的账本数据不完整。');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(bundle);
    } on FormatException {
      throw const LanTransferException('手机返回的账本数据无法解析。');
    }
    if (bytes.length > maxBundleBytes) {
      throw const LanTransferException('账本超过 16 MB，请改用 .fjob 文件。');
    }
    return LanPullPayload(fileName: fileName, bytes: bytes);
  }

  /// Pushes the PC's ledger after the phone started a "receive from PC" session.
  Future<void> push({
    required LanAddress address,
    required String code,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxBundleBytes) {
      throw const LanTransferException('账本超过 16 MB，请改用 .fjob 文件。');
    }
    final info = await probe(address);
    if (info.mode != LanTransferMode.receive) {
      throw const LanTransferException(
        '手机当前在「发送到电脑」模式；请让手机选择「从电脑接收」。',
      );
    }
    final key = await LanCrypto.deriveKey(code: code, salt: info.saltBytes);
    final payload = await _post(
      address,
      key,
      info,
      {
        'v': lanProtocolVersion,
        'challenge': info.challengeBase64,
        'client': 'windows',
        'action': 'push',
        'fileName': sanitizeLanFileName(fileName),
        'bundle': base64Encode(bytes),
      },
    );
    if (payload['ok'] != true) {
      throw const LanTransferException('手机没有确认收到账本，请重试。');
    }
  }

  Future<Map<String, dynamic>> _post(
    LanAddress address,
    SecretKey key,
    LanSessionInfo info,
    Map<String, Object?> request,
  ) async {
    final envelope = await LanCrypto.seal(key, request, context: 'transfer');
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.http(address.authority, '/transfer'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(envelope.toJson()),
          )
          .timeout(transferTimeout);
    } on TimeoutException {
      throw const LanTransferException('传输超时，请确认手机仍停留在互传页面。');
    } on Object {
      throw const LanTransferException('传输中断，请确认手机仍在互传页面后重试。');
    }
    if (response.statusCode != 200) {
      throw _mapError(response.statusCode);
    }
    final LanEnvelope responseEnvelope;
    try {
      responseEnvelope = LanEnvelope.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } on FormatException {
      throw const LanTransferException('手机返回的数据无法解析。');
    }
    return LanCrypto.open(key, responseEnvelope, context: 'transfer');
  }

  LanTransferException _mapError(int status) => switch (status) {
        401 => const LanTransferException('配对码不正确或会话已失效，请在手机上确认后重试。'),
        409 => const LanTransferException('手机端当前模式不匹配，请在手机上重新开始互传。'),
        410 => const LanTransferException('互传会话已结束，请在手机上重新开始。'),
        413 => const LanTransferException('账本超过 16 MB，请改用 .fjob 文件。'),
        503 => const LanTransferException('手机端账本暂不可用，请稍后重试。'),
        _ => LanTransferException('手机端返回错误（HTTP $status）。'),
      };

  void close() {
    if (_ownsClient) _client.close();
  }
}
