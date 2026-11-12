import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'code.dart';
import 'protocol.dart';

final class LanEnvelope {
  const LanEnvelope({
    required this.nonceBase64,
    required this.cipherTextBase64,
    required this.macBase64,
  });

  final String nonceBase64;
  final String cipherTextBase64;
  final String macBase64;

  Map<String, Object?> toJson() => {
        'nonce': nonceBase64,
        'cipherText': cipherTextBase64,
        'mac': macBase64,
      };

  factory LanEnvelope.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const LanTransferException('传输数据格式不正确。');
    }
    final nonce = raw['nonce'];
    final cipherText = raw['cipherText'];
    final mac = raw['mac'];
    if (nonce is! String || cipherText is! String || mac is! String) {
      throw const LanTransferException('传输数据格式不正确。');
    }
    try {
      final nonceBytes = base64Decode(nonce);
      final macBytes = base64Decode(mac);
      if (nonceBytes.length != 12 || macBytes.length != 16) {
        throw const FormatException();
      }
      base64Decode(cipherText);
    } on FormatException {
      throw const LanTransferException('传输数据格式不正确。');
    }
    return LanEnvelope(
      nonceBase64: nonce,
      cipherTextBase64: cipherText,
      macBase64: mac,
    );
  }
}

/// AES-256-GCM with an HKDF-SHA256 key derived from the one-time pairing code
/// and the session salt. Context strings are authenticated as AAD so a request
/// envelope cannot be reflected as a response envelope.
final class LanCrypto {
  LanCrypto._();

  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<SecretKey> deriveKey({
    required String code,
    required List<int> salt,
  }) async {
    if (!LanTransferCode.isValid(code)) {
      throw const LanTransferException('配对码格式不正确。');
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(LanTransferCode.normalize(code))),
      nonce: salt,
      info: utf8.encode('fjob-lan-v1/key'),
    );
  }

  static Future<LanEnvelope> seal(
    SecretKey key,
    Map<String, Object?> payload, {
    required String context,
  }) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode('fjob-lan-v1/$context'),
    );
    return LanEnvelope(
      nonceBase64: base64Encode(box.nonce),
      cipherTextBase64: base64Encode(box.cipherText),
      macBase64: base64Encode(box.mac.bytes),
    );
  }

  static Future<Map<String, dynamic>> open(
    SecretKey key,
    LanEnvelope envelope, {
    required String context,
  }) async {
    try {
      final box = SecretBox(
        base64Decode(envelope.cipherTextBase64),
        nonce: base64Decode(envelope.nonceBase64),
        mac: Mac(base64Decode(envelope.macBase64)),
      );
      final clearText = await _cipher.decrypt(
        box,
        secretKey: key,
        aad: utf8.encode('fjob-lan-v1/$context'),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return decoded;
    } on SecretBoxAuthenticationError {
      throw const LanTransferException('配对码不正确或会话已失效。');
    } on FormatException {
      throw const LanTransferException('传输数据格式不正确。');
    }
  }
}
