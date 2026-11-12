import 'dart:convert';
import 'dart:typed_data';

const int lanProtocolVersion = 1;
const int defaultMaxBundleBytes = 16 * 1024 * 1024;

enum LanTransferMode { send, receive }

final class LanTransferException implements Exception {
  const LanTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class LanSessionInfo {
  const LanSessionInfo({
    required this.version,
    required this.mode,
    required this.device,
    required this.saltBase64,
    required this.challengeBase64,
    required this.expiresAt,
  });

  final int version;
  final LanTransferMode mode;
  final String device;
  final String saltBase64;
  final String challengeBase64;
  final DateTime expiresAt;

  List<int> get saltBytes => base64Decode(saltBase64);

  factory LanSessionInfo.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const LanTransferException('手机返回的会话信息格式不正确。');
    }
    final version = raw['v'];
    final modeName = raw['mode'];
    final device = raw['device'];
    final salt = raw['salt'];
    final challenge = raw['challenge'];
    final expiresAt = raw['expiresAt'];
    if (version != lanProtocolVersion ||
        modeName is! String ||
        device is! String ||
        salt is! String ||
        challenge is! String ||
        expiresAt is! String) {
      throw const LanTransferException('手机返回的会话信息格式不正确。');
    }
    final LanTransferMode mode;
    switch (modeName) {
      case 'send':
        mode = LanTransferMode.send;
      case 'receive':
        mode = LanTransferMode.receive;
      default:
        throw const LanTransferException('手机返回的会话模式无法识别。');
    }
    final DateTime expiry;
    try {
      expiry = DateTime.parse(expiresAt).toUtc();
      base64Decode(salt);
      base64Decode(challenge);
    } on FormatException {
      throw const LanTransferException('手机返回的会话信息格式不正确。');
    }
    if (expiry.isBefore(DateTime.now().toUtc())) {
      throw const LanTransferException('手机上的互传会话已过期，请重新开始。');
    }
    return LanSessionInfo(
      version: version as int,
      mode: mode,
      device: device,
      saltBase64: salt,
      challengeBase64: challenge,
      expiresAt: expiry,
    );
  }
}

final class LanPullPayload {
  const LanPullPayload({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

enum LanServerEventType { listening, paired, pulled, pushed, failed, stopped }

final class LanServerEvent {
  const LanServerEvent(this.type, {this.message});

  final LanServerEventType type;
  final String? message;
}

String sanitizeLanFileName(String name) {
  var cleaned =
      name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '_').trim();
  if (cleaned.isEmpty) cleaned = 'fjob-lan.fjob';
  return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
}
